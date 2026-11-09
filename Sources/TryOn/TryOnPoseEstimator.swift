import simd

struct TryOnPoseSolution {
  var yaw: Float
  var surface: TryOnSurface
  var pose: TryOnBodyPose
}

/// Supported standing, arms-separated surfaces. Search bands only select real
/// intersections/vertices; no joint is assigned a guessed fraction/depth.
/// Front orientation uses observed feet relative to ankles, not a face photo.
enum TryOnPoseEstimator {
  static func solve(mesh: TryOnSourceMesh) throws -> TryOnPoseSolution {
    try Task.checkCancellation()
    var lowest = Float.greatestFiniteMagnitude, highest = -Float.greatestFiniteMagnitude
    for point in mesh.points { lowest = min(lowest, point.y); highest = max(highest, point.y) }
    let height = highest - lowest
    guard height > 0.8 else { throw TryOnError.pose }
    var count = 0.0, sumX = 0.0, sumZ = 0.0, sumXX = 0.0, sumZZ = 0.0, sumXZ = 0.0
    for point in mesh.points where point.y > lowest + height * 0.48 && point.y < lowest + height * 0.81 {
      let x = Double(point.x), z = Double(point.z)
      count += 1; sumX += x; sumZ += z; sumXX += x*x; sumZZ += z*z; sumXZ += x*z
    }
    guard count > 100 else { throw TryOnError.pose }
    let xx = sumXX - sumX*sumX/count, zz = sumZZ - sumZ*sumZ/count, xz = sumXZ - sumX*sumZ/count
    guard max(xx, zz) > 0.01 else { throw TryOnError.pose }
    var yaw = Float(atan2(2 * xz, xx - zz) / 2)
    var cosine = cos(yaw), sine = sin(yaw)
    func rotated(_ point: SIMD3<Float>) -> SIMD3<Float> {
      SIMD3(cosine * point.x + sine * point.z, point.y, -sine * point.x + cosine * point.z)
    }
    var foot: Float = 0, ankle: Float = 0
    var footCount = 0, ankleCount = 0
    for point in mesh.points {
      let fraction = (point.y - lowest) / height
      if fraction < 0.055 { foot += rotated(point).z; footCount += 1 }
      if fraction > 0.10 && fraction < 0.16 { ankle += rotated(point).z; ankleCount += 1 }
    }
    guard footCount >= 20, ankleCount >= 20 else { throw TryOnError.pose }
    let toeDirection = foot / Float(footCount) - ankle / Float(ankleCount)
    // Symmetric, truncated or obscured feet do not establish a front. Fail with
    // capture guidance rather than silently reversing an unobserved orientation.
    guard abs(toeDirection) > height * 0.009 else { throw TryOnError.pose }
    if toeDirection < 0 { yaw += .pi; cosine = cos(yaw); sine = sin(yaw) }
    let positions = mesh.points.map(rotated)
    let surface = try TryOnSurface(points: positions, triangles: mesh.triangles)
    try Task.checkCancellation()

    func rows(_ lower: Float, _ upper: Float) -> [TryOnSurface.Section] {
      stride(from: lowest + height * lower, through: lowest + height * upper, by: height * 0.004)
        .compactMap { surface.section($0) }
    }
    let neckRows = rows(0.82, 0.87).filter {
      guard let part = $0.torso else { return false }
      return part.width > height * 0.025 && part.width < height * 0.15 && part.maximumZ - part.minimumZ > 0.03
    }
    guard let narrowest = neckRows.compactMap({ $0.torso?.width }).min(),
          let chest = rows(0.67, 0.75).lazy.filter({ $0.components.count >= 3 }).compactMap(\.torso).max(by: { $0.width < $1.width }),
          let neckRow = neckRows.filter({ ($0.torso?.width ?? .infinity) <= (narrowest + chest.width) * 0.5 }).min(by: { $0.y < $1.y }),
          let neckSection = neckRow.torso,
          let hipsRow = rows(0.47, 0.56).max(by: { ($0.torso?.width ?? 0) < ($1.torso?.width ?? 0) }),
          let hipSection = hipsRow.torso else { throw TryOnError.pose }
    let neck = SIMD3(neckSection.center.x, neckRow.y, neckSection.center.y)
    let hips = SIMD3(hipSection.center.x, hipsRow.y, hipSection.center.y)
    guard neck.y > hips.y + 0.3 else { throw TryOnError.pose }

    func shoulder(_ side: Float) throws -> SIMD3<Float> {
      var selected: SIMD3<Float>?
      var best = -Float.infinity
      for point in positions {
        let lateral = (point.x - neck.x) * side
        guard point.y >= lowest + height * 0.74, point.y <= lowest + height * 0.84,
              lateral >= chest.width * 0.57, lateral <= chest.width * 0.86 else { continue }
        let score = point.y - abs(lateral - chest.width * 0.75) * 1.5
        if score > best { best = score; selected = point }
      }
      guard let point = selected,
            let depth = surface.depth(x: point.x, y: point.y - 0.003) else { throw TryOnError.pose }
      return SIMD3(point.x, point.y, (depth.front + depth.back) / 2)
    }
    let left = try shoulder(-1), right = try shoulder(1)
    guard right.x - left.x > 0.18, right.x - left.x < 0.8,
          abs(left.y - right.y) < height * 0.10 else { throw TryOnError.pose }

    func elbow(_ side: Float, shoulder: SIMD3<Float>) throws -> SIMD3<Float> {
      var observed: [SIMD3<Float>] = []
      for row in rows(0.59, 0.74) where row.y < shoulder.y - height * 0.08 {
        guard let central = row.torso else { continue }
        let limbs = row.components.filter {
          ($0.center.x - central.center.x) * side > central.width * 0.5 + 0.012
            && $0.width > 0.025 && $0.width < 0.20
        }
        if let limb = limbs.min(by: { abs($0.center.x - shoulder.x) < abs($1.center.x - shoulder.x) }) {
          observed.append(SIMD3(limb.center.x, row.y, limb.center.y))
        }
      }
      guard observed.count >= 6 else { throw TryOnError.pose }
      // Median observed upper-arm/forearm section: stable against a few noisy
      // scan triangles, with actual lateral position and depth retained.
      let point = observed[observed.count / 2]
      let length = simd_distance(point, shoulder)
      guard length > 0.12, length < 0.65, (point.x - shoulder.x) * side > 0.025 else { throw TryOnError.pose }
      return point
    }
    return TryOnPoseSolution(yaw: yaw, surface: surface,
      pose: TryOnBodyPose(neck: neck, leftShoulder: right, rightShoulder: left,
                          leftElbow: try elbow(1, shoulder: right), rightElbow: try elbow(-1, shoulder: left), hips: hips))
  }
}
