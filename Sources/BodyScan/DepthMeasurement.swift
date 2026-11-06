import Foundation
import CoreGraphics
import CoreVideo
import simd

enum DepthMeasurement {
    static func point(
        imagePoint: CGPoint,
        depthMeters: Float,
        intrinsics: simd_float3x3,
        imageSize: CGSize
    ) throws -> SIMD3<Float> {
        guard imageSize.width.isFinite, imageSize.height.isFinite,
              imageSize.width > 0, imageSize.height > 0,
              imagePoint.x.isFinite, imagePoint.y.isFinite,
              imagePoint.x >= 0, imagePoint.x < 1,
              imagePoint.y >= 0, imagePoint.y < 1 else {
            throw BodyScanError.invalidGeometry
        }
        guard depthMeters.isFinite, depthMeters > 0 else {
            throw BodyScanError.invalidDepth
        }

        for column in 0..<3 {
            for row in 0..<3 where !intrinsics[column][row].isFinite {
                throw BodyScanError.invalidGeometry
            }
        }
        let fx = intrinsics[0][0]
        let fy = intrinsics[1][1]
        let cx = intrinsics[2][0]
        let cy = intrinsics[2][1]
        guard fx > 0, fy > 0, cx >= 0, cy >= 0 else {
            throw BodyScanError.invalidGeometry
        }

        let pixelX = Float(imagePoint.x * imageSize.width)
        let pixelY = Float(imagePoint.y * imageSize.height)
        guard pixelX.isFinite, pixelY.isFinite else {
            throw BodyScanError.invalidGeometry
        }
        let inverse = simd_inverse(intrinsics)
        let ray = inverse * SIMD3<Float>(pixelX, pixelY, 1)
        guard ray.x.isFinite, ray.y.isFinite, ray.z.isFinite, ray.z != 0 else {
            throw BodyScanError.invalidGeometry
        }
        let scale = depthMeters / ray.z
        let result = ray * scale
        guard scale.isFinite, result.x.isFinite, result.y.isFinite, result.z.isFinite else {
            throw BodyScanError.invalidGeometry
        }
        return result
    }

    static func imagePoint(
        viewPoint: CGPoint,
        viewportSize: CGSize,
        imageToView: CGAffineTransform
    ) throws -> CGPoint {
        guard viewportSize.width.isFinite, viewportSize.height.isFinite,
              viewportSize.width > 0, viewportSize.height > 0,
              viewPoint.x.isFinite, viewPoint.y.isFinite else {
            throw BodyScanError.invalidGeometry
        }
        guard imageToView.a.isFinite, imageToView.b.isFinite,
              imageToView.c.isFinite, imageToView.d.isFinite,
              imageToView.tx.isFinite, imageToView.ty.isFinite else {
            throw BodyScanError.invalidGeometry
        }
        let determinant = imageToView.a * imageToView.d - imageToView.b * imageToView.c
        guard determinant.isFinite, determinant != 0 else {
            throw BodyScanError.invalidGeometry
        }
        let normalizedViewPoint = CGPoint(
            x: viewPoint.x / viewportSize.width,
            y: viewPoint.y / viewportSize.height
        )
        let imagePoint = normalizedViewPoint.applying(imageToView.inverted())
        guard imagePoint.x.isFinite, imagePoint.y.isFinite,
              imagePoint.x >= 0, imagePoint.x < 1,
              imagePoint.y >= 0, imagePoint.y < 1 else {
            throw BodyScanError.invalidGeometry
        }
        return imagePoint
    }

    static func viewportTransform(
        imageSize: CGSize,
        viewportSize: CGSize,
        imageToView: CGAffineTransform
    ) throws -> CGAffineTransform {
        guard imageSize.width.isFinite, imageSize.height.isFinite,
              imageSize.width > 0, imageSize.height > 0,
              viewportSize.width.isFinite, viewportSize.height.isFinite,
              viewportSize.width > 0, viewportSize.height > 0 else {
            throw BodyScanError.invalidGeometry
        }
        guard imageToView.a.isFinite, imageToView.b.isFinite,
              imageToView.c.isFinite, imageToView.d.isFinite,
              imageToView.tx.isFinite, imageToView.ty.isFinite else {
            throw BodyScanError.invalidGeometry
        }
        let determinant = imageToView.a * imageToView.d - imageToView.b * imageToView.c
        guard determinant.isFinite, determinant != 0 else {
            throw BodyScanError.invalidGeometry
        }

        let transform = CGAffineTransform(
            a: viewportSize.width * imageToView.a / imageSize.width,
            b: viewportSize.height * imageToView.b / imageSize.width,
            c: viewportSize.width * imageToView.c / imageSize.height,
            d: viewportSize.height * imageToView.d / imageSize.height,
            tx: viewportSize.width * imageToView.tx,
            ty: viewportSize.height * imageToView.ty
        )
        guard transform.a.isFinite, transform.b.isFinite,
              transform.c.isFinite, transform.d.isFinite,
              transform.tx.isFinite, transform.ty.isFinite else {
            throw BodyScanError.invalidGeometry
        }
        return transform
    }


    static func sample(
        imagePoint: CGPoint,
        depthMap: CVPixelBuffer,
        confidenceMap: CVPixelBuffer
    ) throws -> Float {
        guard imagePoint.x.isFinite, imagePoint.y.isFinite,
              imagePoint.x >= 0, imagePoint.x < 1,
              imagePoint.y >= 0, imagePoint.y < 1 else {
            throw BodyScanError.invalidGeometry
        }
        guard CVPixelBufferGetPixelFormatType(depthMap) == kCVPixelFormatType_DepthFloat32,
              CVPixelBufferGetPixelFormatType(confidenceMap) == kCVPixelFormatType_OneComponent8 else {
            throw BodyScanError.unsupportedDepth
        }
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        guard width > 0, height > 0,
              CVPixelBufferGetWidth(confidenceMap) == width,
              CVPixelBufferGetHeight(confidenceMap) == height else {
            throw BodyScanError.invalidDepth
        }

        guard CVPixelBufferLockBaseAddress(depthMap, .readOnly) == kCVReturnSuccess else {
            throw BodyScanError.invalidDepth
        }
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        guard CVPixelBufferLockBaseAddress(confidenceMap, .readOnly) == kCVReturnSuccess else {
            throw BodyScanError.invalidDepth
        }
        defer { CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly) }

        let depthRowBytes = CVPixelBufferGetBytesPerRow(depthMap)
        let confidenceRowBytes = CVPixelBufferGetBytesPerRow(confidenceMap)
        guard depthRowBytes >= width * MemoryLayout<Float32>.size,
              confidenceRowBytes >= width else {
            throw BodyScanError.invalidDepth
        }
        guard let depthBase = CVPixelBufferGetBaseAddress(depthMap),
              let confidenceBase = CVPixelBufferGetBaseAddress(confidenceMap) else {
            throw BodyScanError.invalidDepth
        }

        let centerX = Int(imagePoint.x * CGFloat(width))
        let centerY = Int(imagePoint.y * CGFloat(height))
        let minX = max(0, centerX - 2)
        let maxX = min(width - 1, centerX + 2)
        let minY = max(0, centerY - 2)
        let maxY = min(height - 1, centerY + 2)
        return try withUnsafeTemporaryAllocation(of: Float.self, capacity: 25) { samples in
            var sampleCount = 0
            for y in minY...maxY {
                let depthRow = depthBase.advanced(by: y * depthRowBytes).assumingMemoryBound(to: UInt8.self)
                let confidenceRow = confidenceBase.advanced(by: y * confidenceRowBytes).assumingMemoryBound(to: UInt8.self)
                for x in minX...maxX {
                    guard confidenceRow[x] >= 1 else { continue }
                    let depth = depthRow.advanced(by: x * MemoryLayout<Float32>.size)
                        .withMemoryRebound(to: Float32.self, capacity: 1) { $0.pointee }
                    if depth.isFinite, depth > 0 {
                        samples[sampleCount] = depth
                        sampleCount += 1
                    }
                }
            }
            guard sampleCount >= 5 else {
                throw BodyScanError.insufficientConfidence
            }

            for index in 1..<sampleCount {
                let value = samples[index]
                var insertionIndex = index
                while insertionIndex > 0, samples[insertionIndex - 1] > value {
                    samples[insertionIndex] = samples[insertionIndex - 1]
                    insertionIndex -= 1
                }
                samples[insertionIndex] = value
            }
            var nearestCount = sampleCount
            if sampleCount > 1 {
                for index in 1..<sampleCount where samples[index] - samples[index - 1] > 0.04 {
                    nearestCount = index
                    break
                }
            }
            guard nearestCount >= 5, nearestCount * 2 > sampleCount else {
                throw BodyScanError.insufficientConfidence
            }
            let middle = nearestCount / 2
            if nearestCount.isMultiple(of: 2) {
                return samples[middle - 1] + (samples[middle] - samples[middle - 1]) / 2
            }
            return samples[middle]
        }
    }
}
