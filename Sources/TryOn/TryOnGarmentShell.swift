import Foundation
import simd

/// One continuous outer garment surface: observed torso envelopes joined to
/// observed arm envelopes. No body geometry is synthesized or changed. This is
/// bounded illustrative geometry, not a fabric or physical-fit simulation.
enum TryOnGarmentShell {
  private struct Row {
    var y: Float
    var center: SIMD2<Float>
    var radii: [Float]
    var ring: TryOnRing

    func distance(_ point: SIMD3<Float>) -> Float {
      let delta = SIMD2(point.x,point.z)-center
      var angle = atan2(delta.x,delta.y)
      if angle < 0 { angle += 2 * .pi }
      let coordinate = angle * 64 / (2 * .pi)
      let first = Int(coordinate) % 64
      let fraction = coordinate-Float(Int(coordinate))
      let radius = radii[first] + (radii[(first+1)%64]-radii[first])*fraction
      return simd_length(delta)-radius
    }
  }

  private struct Sleeve {
    var origin: SIMD3<Float>
    var axis: SIMD3<Float>
    var side: SIMD3<Float>
    var front: SIMD3<Float>
    var radius: Float
    var length: Float
    var flatOrigin: SIMD2<Float>
    var flatAxis: SIMD2<Float>
    var flatSide: SIMD2<Float>
    var flatHalfWidth: Float
    var meterX: Float
    var meterY: Float

    func coordinates(_ point: SIMD3<Float>) -> (along: Float, radial: SIMD2<Float>) {
      let delta = point-origin
      return (simd_dot(delta,axis),SIMD2(simd_dot(delta,side),simd_dot(delta,front)))
    }
    func distance(_ point: SIMD3<Float>) -> Float {
      let coordinate = coordinates(point)
      return max(simd_length(coordinate.radial)-radius,max(-coordinate.along-radius*0.5,coordinate.along-length))
    }
    func cuffCut(_ point: SIMD3<Float>, step: Float) -> Float {
      let c = coordinates(point)
      // Local cut only: a global cuff plane would incorrectly cut the hem.
      if c.along > length-step*2 && simd_length(c.radial) < radius+step*2 {
        return length-step*0.5-c.along
      }
      return 1
    }
    func uv(_ point: SIMD3<Float>) -> SIMD2<Float> {
      let coordinate = coordinates(point)
      let angle = atan2(coordinate.radial.x,abs(coordinate.radial.y))
      let flat = flatOrigin + flatAxis*coordinate.along + flatSide*(angle/(.pi/2)*flatHalfWidth)
      return SIMD2(flat.x/meterX,-flat.y/meterY)
    }
  }

  static func build(surface: TryOnSurface,pose: TryOnBodyPose,pattern: TryOnPattern,dimensions: GarmentScanDimensions) throws -> TryOnShape {
    let p = pattern.points
    guard dimensions.isValid,p.count == 25,pattern.width > 1,pattern.height > 1,
          pattern.alpha.count == pattern.width*pattern.height,
          p.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }),
          p[19].x-p[11].x > 0.2,p[15].y-p[1].y > 0.4 else { throw TryOnError.shirt }
    let meterX = Float(dimensions.bodyWidthM)/(p[19].x-p[11].x)
    let meterY = Float(dimensions.lengthM)/(p[15].y-p[1].y)
    let sleevePhotoWidth = p[22].x-p[8].x-(p[19].x-p[11].x)
    guard sleevePhotoWidth > 0.05 else { throw TryOnError.shirt }
    let sleeveMeterX = Float(dimensions.sleeveSpanM-dimensions.bodyWidthM)/sleevePhotoWidth
    guard sleeveMeterX > 0,sleeveMeterX < 3 else { throw TryOnError.shirt }
    let shoulderWidth = pose.leftShoulder.x-pose.rightShoulder.x
    guard shoulderWidth > 0.18,shoulderWidth < 0.7,pose.neck.y > pose.hips.y+0.15,
          let hips = surface.section(pose.hips.y)?.torso else { throw TryOnError.pose }
    let hem = pose.neck.y-Float(dimensions.lengthM)
    guard hem > surface.minimum.y+0.02 else { throw TryOnError.geometry }
    let step: Float = 0.012
    let rowCount = Int(ceil((pose.neck.y-hem)/step))+1
    let rowStep = (pose.neck.y-hem)/Float(rowCount-1)
    var rows: [Row] = []; rows.reserveCapacity(rowCount)
    var needsRoom = false
    for i in 0..<rowCount {
      try Task.checkCancellation()
      let y = hem+Float(i)*rowStep
      let t = min(1,max(0,(pose.neck.y-y)/(pose.neck.y-pose.hips.y)))
      let centerX = pose.neck.x+(pose.hips.x-pose.neck.x)*t
      let neckCircumference = (p[5].x-p[1].x)*meterX*2
      let chestBlend = min(1,max(0,(pose.neck.y-y)/max(0.04,pose.neck.y-(pose.leftShoulder.y+pose.rightShoulder.y)*0.5+0.04)))
      let circumference = neckCircumference+(Float(dimensions.bodyWidthM)*2-neckCircumference)*chestBlend
      // Preserve the original observed-ray admission before convex clothing
      // spans torso concavities. A hull must never conceal missing scan coverage.
      let observed = y >= pose.hips.y
        ? try TryOnRing.make(segments: surface.section(at: y),centerX: centerX,shoulderWidth: shoulderWidth,circumference: circumference)
        : nil
      let segments = surface.garmentSection(at: y,bridgeBelow: pose.hips.y,halfWidth: hips.width*0.65)
      let ring = try TryOnRing.make(segments: segments,centerX: centerX,shoulderWidth: shoulderWidth,circumference: circumference)
      let center = (ring.points[0]+ring.points[32])*0.5
      rows.append(Row(y: y,center: center,radii: ring.points.map { simd_distance($0,center) },ring: ring))
      if y > pose.hips.y && chestBlend > 0.9 { needsRoom = needsRoom || (observed?.tight ?? ring.tight) }
    }
    let left = try sleeve(surface: surface,shoulder: pose.rightShoulder,elbow: pose.rightElbow,
      shoulderUV: p[6],pitUV: p[11],outerUV: p[8],innerUV: p[10],meterX: sleeveMeterX,meterY: meterY)
    let right = try sleeve(surface: surface,shoulder: pose.leftShoulder,elbow: pose.leftElbow,
      shoulderUV: p[24],pitUV: p[19],outerUV: p[22],innerUV: p[20],meterX: sleeveMeterX,meterY: meterY)
    func torso(_ point: SIMD3<Float>) -> Float {
      let coordinate = min(Float(rowCount-1),max(0,(point.y-hem)/rowStep))
      let first = min(rowCount-2,Int(coordinate)), fraction = coordinate-Float(first)
      return rows[first].distance(point)*(1-fraction)+rows[first+1].distance(point)*fraction
    }
    func smoothUnion(_ a: Float,_ b: Float) -> Float {
      let blend = max(0,0.018-abs(a-b))
      return min(a,b)-blend*blend/(4*0.018)
    }
    func field(_ point: SIMD3<Float>) -> Float { smoothUnion(smoothUnion(torso(point),left.distance(point)),right.distance(point)) }
    // Point 0 has no native confidence admission gate. Derive the opening from
    // actual image alpha instead of letting a weak prediction cut the torso.
    let neckX = min(pattern.width-1,max(0,Int((p[1].x+p[5].x)*0.5*Float(pattern.width-1))))
    let neckStart = Int(min(p[1].y,p[5].y)*Float(pattern.height-1))
    let neckEnd = Int(min(p[11].y,p[19].y)*Float(pattern.height-1))
    guard neckEnd > neckStart,
          let neckBottom = (neckStart...neckEnd).first(where: { pattern.alpha[$0*pattern.width+neckX] > 240 }) else { throw TryOnError.shirt }
    let frontDrop = max(0,Float(neckBottom)/Float(pattern.height-1)-p[1].y)*meterY
    func cut(_ point: SIMD3<Float>,_ kind: Int) -> Float {
      if kind == 1 { return left.cuffCut(point,step: step) }
      if kind == 2 { return right.cuffCut(point,step: step) }
      let delta = SIMD2(point.x-pose.neck.x,point.z-rows[rowCount-1].center.y)
      let cosine = delta.y/max(0.001,simd_length(delta))
      let drop = cosine >= 0 ? frontDrop*cosine*cosine : min(0.02,frontDrop*0.2)*cosine*cosine
      return pose.neck.y-drop-point.y
    }
    var minimum = SIMD3<Float>(.greatestFiniteMagnitude,hem,.greatestFiniteMagnitude)
    var maximum = SIMD3<Float>(-.greatestFiniteMagnitude,pose.neck.y,-.greatestFiniteMagnitude)
    for row in rows { for point in row.ring.points {
      minimum.x = min(minimum.x,point.x); minimum.z = min(minimum.z,point.y)
      maximum.x = max(maximum.x,point.x); maximum.z = max(maximum.z,point.y)
    } }
    for sleeve in [left,right] { for center in [sleeve.origin,sleeve.origin+sleeve.axis*sleeve.length] {
      minimum.x = min(minimum.x,center.x-sleeve.radius); minimum.z = min(minimum.z,center.z-sleeve.radius)
      maximum.x = max(maximum.x,center.x+sleeve.radius); maximum.z = max(maximum.z,center.z+sleeve.radius)
    } }
    minimum.x -= step*2; minimum.z -= step*2; maximum.x += step*2; maximum.z += step*2
    var polygonizer = Polygonizer(minimum: minimum,maximum: maximum,step: step)
    var mesh = try polygonizer.build(field: field,cut: cut)
    // All front/rear/side triangles share vertices. Surface-aware clearance
    // cannot tear a panel away from its sleeve or open a seam.
    for i in mesh.positions.indices {
      let point = mesh.positions[i]
      if let depth = surface.depth(x: point.x,y: point.y) {
        let front = point.z >= (depth.front+depth.back)*0.5
        let z = front ? max(point.z,depth.front+0.006) : min(point.z,depth.back-0.006)
        guard abs(z-point.z) <= 0.065 else { throw TryOnError.surface }
        mesh.positions[i].z = z
      }
    }
    mesh = try mesh.removingDegenerateFaces()
    // Reproject only unsupported UV locations onto the actual opaque source
    // image. A non-convex flat sleeve must not punch alpha holes into a sewn
    // 3D arm/torso junction. No replacement texture is manufactured.
    var nearest = Array(repeating: -1,count: pattern.alpha.count), queue: [Int] = []
    queue.reserveCapacity(pattern.alpha.count)
    for y in 2..<pattern.height-2 { for x in 2..<pattern.width-2 {
      let i = y*pattern.width+x
      if pattern.alpha[i] > 245,pattern.alpha[i-2] > 245,pattern.alpha[i+2] > 245,
         pattern.alpha[i-pattern.width*2] > 245,pattern.alpha[i+pattern.width*2] > 245 {
        nearest[i] = i; queue.append(i)
      }
    } }
    guard !queue.isEmpty else { throw TryOnError.shirt }
    var cursor = 0
    while cursor < queue.count {
      let i = queue[cursor]; cursor += 1
      func visit(_ neighbor: Int) {
        if nearest[neighbor] == -1 { nearest[neighbor] = nearest[i]; queue.append(neighbor) }
      }
      if i % pattern.width > 0 { visit(i-1) }
      if i % pattern.width+1 < pattern.width { visit(i+1) }
      if i >= pattern.width { visit(i-pattern.width) }
      if i+pattern.width < nearest.count { visit(i+pattern.width) }
    }
    let bodyEdges = (0..<pattern.height).map { row -> SIMD2<Float> in
      let edge = pattern.bodyEdges(at: Float(row)/Float(pattern.height-1))
      return SIMD2(edge.0,edge.1)
    }
    for point in mesh.positions {
      let bodyDistance = torso(point), l = left.distance(point), r = right.distance(point)
      var uv: SIMD2<Float>
      if l < bodyDistance+0.01 && l < r { uv = left.uv(point) }
      else if r < bodyDistance+0.01 { uv = right.uv(point) }
      else {
        let v = p[1].y+(pose.neck.y-point.y)/meterY
        let rowIndex = min(rowCount-1,max(0,Int(round((point.y-hem)/rowStep))))
        let delta = SIMD2(point.x,point.z)-rows[rowIndex].center
        let angle = atan2(delta.x,abs(delta.y))
        let across = angle / .pi+0.5
        let edges: (Float,Float)
        if v < p[6].y {
          let t = min(1,max(0,(v-p[1].y)/max(0.01,p[6].y-p[1].y)))
          edges = (p[1].x+(p[6].x-p[1].x)*t,p[5].x+(p[24].x-p[5].x)*t)
        } else if v < p[11].y {
          let t = (v-p[6].y)/max(0.01,p[11].y-p[6].y)
          edges = (p[6].x+(p[11].x-p[6].x)*t,p[24].x+(p[19].x-p[24].x)*t)
        } else {
          let edge = bodyEdges[min(pattern.height-1,max(0,Int(min(v,p[15].y-0.01)*Float(pattern.height-1))))]
          edges = (edge.x,edge.y)
        }
        uv = SIMD2(edges.0+(edges.1-edges.0)*across,v)
      }
      uv.x = min(p[22].x-0.005,max(p[8].x+0.005,uv.x))
      uv.y = min(1,max(0,uv.y))
      let x = min(pattern.width-1,max(0,Int(round(uv.x*Float(pattern.width-1)))))
      let y = min(pattern.height-1,max(0,Int(round(uv.y*Float(pattern.height-1)))))
      let i = y*pattern.width+x, admitted = nearest[i]
      if admitted != i {
        uv = SIMD2(Float(admitted%pattern.width)/Float(pattern.width-1),Float(admitted/pattern.width)/Float(pattern.height-1))
      }
      mesh.textureCoordinates.append(uv)
    }
    return TryOnShape(mesh: mesh,needsRoom: needsRoom,belowHips: hem < pose.hips.y)
  }

  private static func sleeve(surface: TryOnSurface,shoulder: SIMD3<Float>,elbow: SIMD3<Float>,
                             shoulderUV: SIMD2<Float>,pitUV: SIMD2<Float>,outerUV: SIMD2<Float>,innerUV: SIMD2<Float>,
                             meterX: Float,meterY: Float) throws -> Sleeve {
    let sign: Float = elbow.x > shoulder.x ? 1 : -1
    var observations: [(point: SIMD3<Float>,radius: Float)] = []
    for y in stride(from: shoulder.y-0.02,through: elbow.y,by: -0.009) {
      guard let section = surface.section(y),let torso = section.torso,
            let arm = section.components.lazy.filter({ ($0.center.x-torso.center.x)*sign > torso.width*0.5+0.01 && $0.width < 0.2 })
              .min(by: { abs($0.center.x-shoulder.x) < abs($1.center.x-shoulder.x) }) else { continue }
      observations.append((SIMD3(arm.center.x,y,arm.center.y),(arm.maximumZ-arm.minimumZ)*0.5))
    }
    guard observations.count >= 4,let high = observations.first,let low = observations.last,
          simd_distance(high.point,low.point) > 0.05 else { throw TryOnError.pose }
    let axis = simd_normalize(low.point-high.point)
    guard axis.y < -0.3,axis.x*sign > 0.1 else { throw TryOnError.pose }
    let side = simd_normalize(SIMD3(-axis.y,axis.x,0))
    var front = simd_normalize(simd_cross(side,axis)); if front.z < 0 { front = -front }
    let rootY = shoulder.y-high.radius*abs(side.y)
    let origin = high.point+axis*((rootY-high.point.y)/axis.y)
    func flat(_ uv: SIMD2<Float>) -> SIMD2<Float> { SIMD2(uv.x*meterX,-uv.y*meterY) }
    let flatOrigin = (flat(shoulderUV)+flat(pitUV))*0.5
    let cuff = (flat(outerUV)+flat(innerUV))*0.5
    let length = simd_distance(flatOrigin,cuff)
    guard length > 0.04,length < 0.55 else { throw TryOnError.shirt }
    let flatAxis = simd_normalize(cuff-flatOrigin)
    let flatHalfWidth = simd_distance(flat(outerUV),flat(innerUV))*0.5
    let observedRadius = observations.map(\.radius).max()!
    guard observedRadius > 0.015,observedRadius < 0.15 else { throw TryOnError.surface }
    let radius = max(observedRadius+0.008,min(observedRadius+0.04,flatHalfWidth*2 / .pi))
    return Sleeve(origin: origin,axis: axis,side: side,front: front,radius: radius,length: length,
      flatOrigin: flatOrigin,flatAxis: flatAxis,flatSide: SIMD2(-flatAxis.y,flatAxis.x),flatHalfWidth: flatHalfWidth,meterX: meterX,meterY: meterY)
  }

  private struct Edge: Hashable {
    var a: Int; var b: Int
    init(_ a: Int,_ b: Int) { self.a = min(a,b); self.b = max(a,b) }
  }
  private struct CutEdge: Hashable { var edge: Edge; var cut: Int }
  private struct Polygonizer {
    var minimum: SIMD3<Float>; var maximum: SIMD3<Float>; var step: Float
    private var positions: [SIMD3<Float>] = []
    private var edges: [Edge:Int] = [:]
    private var exact: [Int:Int] = [:]
    private var cutEdges: [CutEdge:Int] = [:]
    private var front: [UInt32] = [], back: [UInt32] = []
    init(minimum: SIMD3<Float>,maximum: SIMD3<Float>,step: Float) { self.minimum = minimum; self.maximum = maximum; self.step = step }
    private static let tetrahedra = [SIMD4(0,5,1,6),SIMD4(0,1,2,6),SIMD4(0,2,3,6),SIMD4(0,3,7,6),SIMD4(0,7,4,6),SIMD4(0,4,5,6)]
    private static let edgeEnds = [SIMD2(0,1),SIMD2(1,2),SIMD2(2,0),SIMD2(0,3),SIMD2(1,3),SIMD2(2,3)]
    private static let cases = [[],[0,3,2],[0,1,4],[1,4,2,2,4,3],[1,2,5],[0,3,5,0,5,1],[0,2,5,0,5,4],[5,4,3],
      [3,4,5],[4,5,0,5,2,0],[1,5,0,5,3,0],[5,2,1],[3,4,2,2,4,1],[4,1,0],[2,3,0],[]]

    mutating func build(field: (SIMD3<Float>)->Float,cut: (SIMD3<Float>,Int)->Float) throws -> TryOnMesh {
      let nx = Int(ceil((maximum.x-minimum.x)/step))+1, ny = Int(ceil((maximum.y-minimum.y)/step))+1, nz = Int(ceil((maximum.z-minimum.z)/step))+1
      guard nx > 2,ny > 2,nz > 2,nx <= 150,ny <= 160,nz <= 100,nx*ny*nz <= 600_000 else { throw TryOnError.geometry }
      let strideY = nx*nz
      let size = SIMD3((maximum.x-minimum.x)/Float(nx-1),(maximum.y-minimum.y)/Float(ny-1),(maximum.z-minimum.z)/Float(nz-1))
      let origin = minimum
      func point(_ id: Int) -> SIMD3<Float> { origin+SIMD3(Float(id%nx),Float(id/strideY),Float((id/nx)%nz))*size }
      var values = [Float](repeating: 0,count: nx*ny*nz)
      for y in 0..<ny {
        try Task.checkCancellation()
        for z in 0..<nz { for x in 0..<nx {
          let id = y*strideY+z*nx+x; values[id] = field(point(id))
        } }
      }
      func finite(_ v: Float) -> Bool { v.isFinite }
      guard values.allSatisfy(finite) else { throw TryOnError.surface }
      for y in 0..<ny-1 {
        try Task.checkCancellation()
        for z in 0..<nz-1 { for x in 0..<nx-1 {
          let a = y*strideY+z*nx+x
          let ids = SIMD8(a,a+1,a+strideY+1,a+strideY,a+nx,a+nx+1,a+nx+strideY+1,a+nx+strideY)
          var inside = 0
          for i in 0..<8 where values[ids[i]] < 0 { inside += 1 }
          if inside == 0 || inside == 8 { continue }
          for tetra in Self.tetrahedra {
            let t = SIMD4(ids[tetra[0]],ids[tetra[1]],ids[tetra[2]],ids[tetra[3]])
            var mask = 0, negative = 0, positive = 0
            for i in 0..<4 { if values[t[i]] < 0 { mask |= 1 << i; negative = t[i] } else { positive = t[i] } }
            let table = Self.cases[mask]
            if table.isEmpty { continue }
            let outward = point(positive)-point(negative)
            for triangle in stride(from: 0,to: table.count,by: 3) {
              var vertices = SIMD3<Int>(repeating: 0)
              for i in 0..<3 {
                let ends = Self.edgeEnds[table[triangle+i]], first = t[ends[0]], second = t[ends[1]]
                let edge = Edge(first,second)
                if let cached = edges[edge] { vertices[i] = cached; continue }
                let fraction = values[first]/(values[first]-values[second])
                let endpoint: Int? = fraction < 0.00001 ? first : fraction > 0.99999 ? second : nil
                if let endpoint,let cached = exact[endpoint] { vertices[i] = cached; edges[edge] = cached; continue }
                let index = positions.count
                positions.append(point(first)+(point(second)-point(first))*fraction)
                vertices[i] = index; edges[edge] = index
                if let endpoint { exact[endpoint] = index }
              }
              if simd_dot(simd_cross(positions[vertices.y]-positions[vertices.x],positions[vertices.z]-positions[vertices.x]),outward) < 0 {
                let old = vertices.y; vertices.y = vertices.z; vertices.z = old
              }
              clippedTriangle(vertices,cut: cut)
            }
          }
        } }
        guard positions.count <= 250_000 else { throw TryOnError.geometry }
      }
      var used = Array(repeating: false,count: positions.count)
      for index in front { used[Int(index)] = true }; for index in back { used[Int(index)] = true }
      var remap = Array(repeating: UInt32.max,count: positions.count), compact: [SIMD3<Float>] = []
      for i in positions.indices where used[i] { remap[i] = UInt32(compact.count); compact.append(positions[i]) }
      guard compact.count >= 100,!front.isEmpty,!back.isEmpty else { throw TryOnError.geometry }
      return TryOnMesh(positions: compact,textureCoordinates: [],front: front.map { remap[Int($0)] },back: back.map { remap[Int($0)] })
    }

    private mutating func clippedTriangle(_ vertices: SIMD3<Int>,cut: (SIMD3<Float>,Int)->Float) {
      var polygon = SIMD8<Int>(vertices.x,vertices.y,vertices.z,0,0,0,0,0), count = 3
      for kind in 0..<3 {
        var next = SIMD8<Int>(repeating: 0), nextCount = 0
        for i in 0..<count {
          let a = polygon[i], b = polygon[(i+1)%count], fa = cut(positions[a],kind), fb = cut(positions[b],kind)
          if fa >= 0 { next[nextCount] = a; nextCount += 1 }
          if (fa < 0) != (fb < 0) {
            let key = CutEdge(edge: Edge(a,b),cut: kind)
            let index: Int
            if let cached = cutEdges[key] { index = cached }
            else {
              let t = fa/(fa-fb)
              if t < 0.00001 { index = a }
              else if t > 0.99999 { index = b }
              else { index = positions.count; positions.append(positions[a]+(positions[b]-positions[a])*t) }
              cutEdges[key] = index
            }
            next[nextCount] = index; nextCount += 1
          }
        }
        count = nextCount; polygon = next
        if count < 3 { return }
      }
      for i in 1..<count-1 {
        let a = polygon[0], b = polygon[i], c = polygon[i+1]
        let normal = simd_cross(positions[b]-positions[a],positions[c]-positions[a])
        if simd_length_squared(normal) <= 1e-14 { continue }
        if normal.z >= 0 { front += [UInt32(a),UInt32(b),UInt32(c)] }
        else { back += [UInt32(a),UInt32(b),UInt32(c)] }
      }
    }
  }
}
