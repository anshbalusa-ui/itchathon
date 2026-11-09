import Darwin
import Metal
import SceneKit
import ImageIO
import RealityKit
import UIKit
import XCTest
@testable import FitCheck

// Installed temporarily by benchmark_onyou.sh, never included in normal tests.
// No camera, personal images, private measurements, or capture-success hook.
final class OnYouPerformanceProbe: XCTestCase {
  private func resources() -> [String:Double] {
    var usage = rusage(); getrusage(RUSAGE_SELF,&usage)
    return ["process_peak_rss_bytes": Double(usage.ru_maxrss),
      "process_user_cpu_seconds": Double(usage.ru_utime.tv_sec)+Double(usage.ru_utime.tv_usec)/1_000_000,
      "process_system_cpu_seconds": Double(usage.ru_stime.tv_sec)+Double(usage.ru_stime.tv_usec)/1_000_000]
  }
  private func attach(_ value: Any,name: String) throws {
    let item = XCTAttachment(data: try JSONSerialization.data(withJSONObject: value,options: [.prettyPrinted,.sortedKeys]),uniformTypeIdentifier: "public.json")
    item.name = name; item.lifetime = .keepAlways; add(item)
  }

  @MainActor
  func testSavedFixturesColdWarmAndRenderedRotation() async throws {
    var records: [[String:Any]] = []
    let before = resources()
    for body in ["a","b"] {
      #if ONYOU_REPAIR_PROBE
      let fixture = try OnYouTryOnFixtures.make(body: body)
      let root = fixture.root, scans = fixture.scans, closet = fixture.closet
      #else
      let root = FileManager.default.temporaryDirectory.appendingPathComponent("OnYouBaselineProbe-"+UUID().uuidString)
      let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "probe-synthetic-avatar-"+body,withExtension: "usdz"))
      let admitted = try ScannedAvatarGeometry.load(url: source)
      let scans = AvatarScanStore(directory: root.appendingPathComponent("avatars"))
      try scans.save(model: source,calibration: admitted.calibration,imageCount: 72,completedPasses: 2)
      let closet = ClosetStore(directory: root.appendingPathComponent("closet"))
      for (name,file,dimensions) in [
        ("Fixture · Tide shirt","probe-synthetic-shirt",GarmentScanDimensions(bodyWidthM: 0.52,lengthM: 0.72,sleeveSpanM: 0.92)),
        ("Fixture · Coral shirt","probe-synthetic-shirt-coral",GarmentScanDimensions(bodyWidthM: 0.58,lengthM: 0.80,sleeveSpanM: 1.0))
      ] {
        let photo = try XCTUnwrap(Bundle(for: Self.self).url(forResource: file,withExtension: "png"))
        _ = try closet.add(name: name,image: Data(contentsOf: photo),dimensions: dimensions,productURL: nil)
      }
      #endif
      defer { try? FileManager.default.removeItem(at: root) }
      let asset = try XCTUnwrap(scans.asset)
      for garment in closet.garments.sorted(by: { $0.name < $1.name }) {
        let builder = TryOnBuilder()
        for iteration in 0..<2 {
          let start = ProcessInfo.processInfo.systemUptime
          let stages = OnYouProbeStages()
          var record: [String:Any] = ["body":body,"garment":garment.name,"iteration":iteration]
          do {
            #if ONYOU_REPAIR_PROBE
            let result = try await builder.build(avatar: asset,garment: garment,photoURL: closet.imageURL(for: garment)) {
              await stages.record($0,elapsedMS: (ProcessInfo.processInfo.systemUptime-start)*1000)
            }
            record["builder_stages"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(result.timings))
            #else
            let result = try await builder.build(avatar: asset,dimensions: XCTUnwrap(garment.dimensions),photoURL: closet.imageURL(for: garment)) {
              await stages.record($0,elapsedMS: (ProcessInfo.processInfo.systemUptime-start)*1000)
            }
            #endif
            let builderMS = (ProcessInfo.processInfo.systemUptime-start)*1000
            record["builder_wall_ms"] = builderMS
            let frames = try render(result,asset: asset,coral: garment.name.contains("Coral"),capture: iteration == 0,label: body+"-"+garment.name)
            record["rendered_frames_ms"] = frames
            record["build_and_first_offscreen_frame_ms"] = builderMS+(try XCTUnwrap(frames["front"]))
            record["outcome"] = "visible garment proven against hidden-frame pixels"
          } catch {
            record["outcome"] = "failed; no successful first garment frame"
            record["failure_wall_ms"] = (ProcessInfo.processInfo.systemUptime-start)*1000
            record["error"] = String(describing: error)
            #if ONYOU_REPAIR_PROBE
            XCTFail("Supported repair fixture \(body)/\(garment.name) failed: \(error)")
            #endif
          }
          record["progress_events"] = await stages.snapshot().map { ["stage":$0.stage as Any,"elapsed_ms":$0.elapsedMS as Any] }
          record["resources_after"] = resources()
          records.append(record)
        }
      }
    }
    try attach(["input":"authored saved USDZs and exact shirt PNGs through production stores; not physical capture",
      "frame_scope":"synchronous native SceneKit offscreen frames, not application navigation latency",
      "runs":records,"resources_before":before,"resources_after":resources()],name:"saved-fixtures-cold-warm-rotation")
  }

  @MainActor
  private func render(_ result: TryOnResult,asset: AvatarScanAsset,coral: Bool,capture: Bool,label: String) throws -> [String:Double] {
    let coordinator = BodySceneView.Coordinator()
    defer { coordinator.scene.rootNode.childNodes.forEach { $0.removeFromParentNode() } }
    #if ONYOU_REPAIR_PROBE
    coordinator.updateScan(ScannedBodySource(url: asset.url,scene: result.avatar))
    #else
    coordinator.updateScan(ScannedBodySource(url: asset.url,referenceHeightCM: asset.record.referenceHeightCM))
    #endif
    coordinator.updateTryOn(result,showing: true)
    let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(),options: nil)
    renderer.scene = coordinator.scene; renderer.pointOfView = coordinator.camera
    var times: [String:Double] = [:]
    for (name,angle) in [("front",Float(0)),("quarter",.pi/4),("left",-.pi/2),("right",.pi/2),("back",.pi)] {
      coordinator.positionCamera(angle: angle,height: asset.record.heightM)
      let start = ProcessInfo.processInfo.systemUptime
      let image = renderer.snapshot(atTime: 0,with: CGSize(width: 480,height: 720),antialiasingMode: .none)
      times[name] = (ProcessInfo.processInfo.systemUptime-start)*1000
      coordinator.updateTryOn(result,showing: false)
      let hidden = renderer.snapshot(atTime: 0,with: CGSize(width: 480,height: 720),antialiasingMode: .none)
      guard try clothPixels(image,coral: coral)-clothPixels(hidden,coral: coral) > 250 else {
        throw NSError(domain: "OnYouBenchmark.RenderedGarmentMissing",code: 1,userInfo: [NSLocalizedDescriptionKey:name])
      }
      coordinator.updateTryOn(result,showing: true)
      if capture {
        let item = XCTAttachment(image: image); item.name = label+"-"+name; item.lifetime = .keepAlways; add(item)
      }
    }
    return times
  }

  private func clothPixels(_ image: UIImage,coral: Bool) throws -> Int {
    let cg = try XCTUnwrap(image.cgImage)
    var bytes = [UInt8](repeating: 0,count: cg.width*cg.height*4)
    try bytes.withUnsafeMutableBytes { data in
      let context = try XCTUnwrap(CGContext(data: data.baseAddress,width: cg.width,height: cg.height,bitsPerComponent: 8,
        bytesPerRow: cg.width*4,space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.draw(cg,in: CGRect(x: 0,y: 0,width: cg.width,height: cg.height))
    }
    var count = 0
    for i in stride(from: 0,to: bytes.count,by: 4) {
      let r = Int(bytes[i]),g = Int(bytes[i+1]),b = Int(bytes[i+2])
      if coral ? r > g+30 && r > b+25 && r > 55 : g > r+25 && b > r+20 && g > 45 { count += 1 }
    }
    return count
  }

  func testNativeRecognitionColdAndWarm() throws {
    let photo = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "GarmentIQ-Shirt",withExtension: "jpg"))
    let data = try Data(contentsOf: photo)
    var records: [[String:Double]] = []
    let before = resources(), loadStart = ProcessInfo.processInfo.systemUptime
    let model = try GarmentLandmarkDetector()
    let modelMS = (ProcessInfo.processInfo.systemUptime-loadStart)*1000
    for iteration in 0..<3 {
      let start = ProcessInfo.processInfo.systemUptime
      let image = try GarmentImageProcessor.normalized(data)
      let imageMS = (ProcessInfo.processInfo.systemUptime-start)*1000
      let inferenceStart = ProcessInfo.processInfo.systemUptime
      var record: [String:Double] = ["iteration":Double(iteration),"model_ms":iteration == 0 ? modelMS : 0,"image_ms":imageMS]
      #if ONYOU_REPAIR_PROBE
      let detection = try model.detectTimed(in: image)
      XCTAssertEqual(detection.points.count,25)
      record["preprocessing_ms"] = detection.timing.preprocessingMS
      record["prediction_ms"] = detection.timing.predictionMS
      record["decoding_ms"] = detection.timing.decodingMS
      #else
      XCTAssertEqual(try model.detect(in: image).count,25)
      #endif
      record["detection_ms"] = (ProcessInfo.processInfo.systemUptime-inferenceStart)*1000
      records.append(record)
    }
    try attach(["input":"existing licensed GarmentIQ-Shirt.jpg; not a synthetic recognition success",
      "runs":records,"resources_before":before,"resources_after":resources()],name:"native-recognition-cold-warm")
  }

  func testIdenticalRingConstructionWorkload() throws {
    let count = 64
    let segments = (0..<count).map { index -> TryOnSegment in
      let a = Float(index)*2 * .pi/Float(count), b = Float(index+1)*2 * .pi/Float(count)
      return TryOnSegment(a: SIMD2(0.18*sin(a),0.13*cos(a)),b: SIMD2(0.18*sin(b),0.13*cos(b)))
    }
    var records: [[String:Double]] = []
    for iteration in 0..<3 {
      let start = ProcessInfo.processInfo.systemUptime
      var checksum: Float = 0
      for _ in 0..<101 {
        let ring = try TryOnRing.make(segments: segments,centerX: 0,shoulderWidth: 0.42,circumference: 1.04)
        checksum += ring.requiredPerimeter
      }
      XCTAssertTrue(checksum.isFinite && checksum > 0)
      records.append(["iteration":Double(iteration),"elapsed_ms":(ProcessInfo.processInfo.systemUptime-start)*1000])
    }
    try attach(["input":"101 identical authored 64-segment metric torso sections; construction only, not retired panel sampling",
      "runs":records,"resources_after":resources()],name:"ring-construction")
  }

  @MainActor
  func testNativePhotoPreflightAvailabilityAndDepthAdmission() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OnYouPreflightProbe-"+UUID().uuidString,isDirectory: true)
    try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let image = UIGraphicsImageRenderer(size: CGSize(width: 240,height: 320)).image { context in
      UIColor.gray.setFill(); context.fill(CGRect(x: 0,y: 0,width: 240,height: 320))
      UIColor.blue.setFill(); context.fill(CGRect(x: 40,y: 60,width: 160,height: 200))
    }
    let cg = try XCTUnwrap(image.cgImage)
    let original = root.appendingPathComponent("0.heic")
    let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(original as CFURL,"public.heic" as CFString,1,nil))
    CGImageDestinationAddImage(destination,cg,nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    var urls = [original]
    for i in 1..<60 { let url = root.appendingPathComponent("\(i).heic"); try FileManager.default.copyItem(at: original,to: url); urls.append(url) }
    var records: [[String:Any]] = []
    for iteration in 0..<3 {
      let start = ProcessInfo.processInfo.systemUptime
      var record: [String:Any] = ["iteration":iteration,"native_capture_supported":BodyCaptureModel.isSupported]
      do {
        let input: AvatarScanInput
        #if ONYOU_REPAIR_PROBE
        input = try await AvatarScanInput.preflight(files: urls)
        #else
        var depth = Set<URL>()
        for file in urls {
          let sample = try await PhotogrammetrySample(contentsOf: file)
          if AvatarScanInput.containsFiniteDepth(sample.depthDataMap) { depth.insert(file) }
        }
        input = AvatarScanInput(imageURLs: Set(urls),depthImageURLs: depth)
        #endif
        record["native_read_status"] = "completed"
        do {
          _ = try input.validate(passes: 2)
          record["admission"] = "incorrectly_accepted"
          XCTFail("Authored RGB without metric depth must never pass capture admission")
        } catch {
          record["admission"] = "rejected"
          record["admission_error"] = String(describing: error)
        }
      } catch {
        record["native_read_status"] = "failed_before_depth_admission"
        record["native_error_type"] = String(reflecting: type(of: error))
        record["native_error"] = String(describing: error)
        record["admission"] = "not_reached"
        // The simulator cannot construct native photogrammetry samples. Preserve that
        // observation instead of calling it successful depth preflight or skipping it.
        if BodyCaptureModel.isSupported { throw error }
      }
      record["elapsed_ms"] = (ProcessInfo.processInfo.systemUptime-start)*1000
      records.append(record)
    }
    try attach(["input":"60 unique authored RGB HEIC paths, NO metric depth; native availability and rejection only, never reconstruction success",
      "runs":records,"resources_after":resources()],name:"native-photo-preflight-availability")
  }
}

private actor OnYouProbeStages {
  struct Event: Sendable { var stage: String; var elapsedMS: Double }
  private var events: [Event] = []
  func record(_ stage: String,elapsedMS: Double) { events.append(Event(stage: stage,elapsedMS: elapsedMS)) }
  func snapshot() -> [Event] { events }
}
