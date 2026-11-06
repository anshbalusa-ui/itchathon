#if DEBUG
import CoreVideo
import Foundation

/// Read-only CoreVideo adapter; locks are scoped strictly to the synchronous borrow.
final class AppleScanEvidence: ScanDepthEvidence {
    private let depth: CVPixelBuffer
    private let confidence: CVPixelBuffer
    private let mask: CVPixelBuffer

    init(depth: CVPixelBuffer, confidence: CVPixelBuffer, mask: CVPixelBuffer) {
        self.depth = depth
        self.confidence = confidence
        self.mask = mask
    }

    func withPlanes<Result>(_ body: (ScanDepthPlane, ScanBytePlane, ScanBytePlane) throws -> Result) throws -> Result {
        guard CVPixelBufferGetPixelFormatType(depth) == kCVPixelFormatType_DepthFloat32,
              CVPixelBufferGetPixelFormatType(confidence) == kCVPixelFormatType_OneComponent8,
              CVPixelBufferGetPixelFormatType(mask) == kCVPixelFormatType_OneComponent8,
              CVPixelBufferGetWidth(depth) == CVPixelBufferGetWidth(confidence),
              CVPixelBufferGetHeight(depth) == CVPixelBufferGetHeight(confidence),
              Self.validStorage(depth, bytesPerPixel: 4), Self.validStorage(confidence, bytesPerPixel: 1),
              Self.validStorage(mask, bytesPerPixel: 1) else { throw ScanEvidenceError.invalidBuffer }

        guard CVPixelBufferLockBaseAddress(depth, .readOnly) == kCVReturnSuccess else { throw ScanEvidenceError.lockFailed }
        defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }
        guard CVPixelBufferLockBaseAddress(confidence, .readOnly) == kCVReturnSuccess else { throw ScanEvidenceError.lockFailed }
        defer { CVPixelBufferUnlockBaseAddress(confidence, .readOnly) }
        guard CVPixelBufferLockBaseAddress(mask, .readOnly) == kCVReturnSuccess else { throw ScanEvidenceError.lockFailed }
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }

        guard let d = CVPixelBufferGetBaseAddress(depth), let c = CVPixelBufferGetBaseAddress(confidence),
              let m = CVPixelBufferGetBaseAddress(mask) else { throw ScanEvidenceError.missingAddress }
        let dRow = CVPixelBufferGetBytesPerRow(depth), cRow = CVPixelBufferGetBytesPerRow(confidence), mRow = CVPixelBufferGetBytesPerRow(mask)
        return try body(
            ScanDepthPlane(bytes: UnsafeRawBufferPointer(start: d, count: dRow * CVPixelBufferGetHeight(depth)), width: CVPixelBufferGetWidth(depth), height: CVPixelBufferGetHeight(depth), bytesPerRow: dRow),
            ScanBytePlane(bytes: UnsafeRawBufferPointer(start: c, count: cRow * CVPixelBufferGetHeight(confidence)), width: CVPixelBufferGetWidth(confidence), height: CVPixelBufferGetHeight(confidence), bytesPerRow: cRow),
            ScanBytePlane(bytes: UnsafeRawBufferPointer(start: m, count: mRow * CVPixelBufferGetHeight(mask)), width: CVPixelBufferGetWidth(mask), height: CVPixelBufferGetHeight(mask), bytesPerRow: mRow))
    }

    private static func validStorage(_ buffer: CVPixelBuffer, bytesPerPixel: Int) -> Bool {
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer), row = CVPixelBufferGetBytesPerRow(buffer)
        guard width > 0, height > 0, row > 0 else { return false }
        let (minimumRow, rowOverflow) = width.multipliedReportingOverflow(by: bytesPerPixel)
        guard !rowOverflow, row >= minimumRow else { return false }
        let (required, sizeOverflow) = row.multipliedReportingOverflow(by: height)
        return !sizeOverflow && CVPixelBufferGetDataSize(buffer) >= required
    }
}

enum ScanEvidenceError: Error { case lockFailed, missingAddress, invalidBuffer }
#endif
