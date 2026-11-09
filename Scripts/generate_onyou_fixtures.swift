#!/usr/bin/env swift
import AppKit
import CryptoKit
import Foundation
import SceneKit
import simd

// Run from the repository root: xcrun swift Scripts/generate_onyou_fixtures.swift /tmp/OnYouAuthoredFixtures
// Requires a NEW/EMPTY output directory. This never writes into personal app storage.
let manager = FileManager.default
func reject(_ message: String) -> Never { fputs(message+"\n",stderr); exit(1) }
guard CommandLine.arguments.count == 2 else { reject("Usage: xcrun swift Scripts/generate_onyou_fixtures.swift EMPTY_OUTPUT_DIRECTORY") }
let output = URL(fileURLWithPath: CommandLine.arguments[1],isDirectory: true)
if manager.fileExists(atPath: output.path) {
  guard try manager.contentsOfDirectory(atPath: output.path).isEmpty else { reject("Output directory must be empty; no files were removed.") }
} else { try manager.createDirectory(at: output,withIntermediateDirectories: true) }
let input = URL(fileURLWithPath: "DevelopmentAssets/HumanShowcase/human-showcase-v1.bin")
let data = try Data(contentsOf: input)
let digest = SHA256.hash(data: data).map { String(format: "%02x",$0) }.joined()
guard digest == "6977bd1aeba54c9f4ef82f9d7f9b8b996d030b2758e226b61dcb9fbccfe4f6e9" else { reject("Pinned CC0 source SHA-256 mismatch") }
var offset = 8
func u32() -> UInt32 { defer { offset += 4 }; return data.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset,as: UInt32.self)) } }
func f32() -> Float { Float(bitPattern: u32()) }
guard String(data: data.prefix(8),encoding: .utf8) == "FCHUMAN1",u32() == 1,data[offset] == 0 else { reject("Unsupported pinned body format") }
offset += 1
let vertexCount = Int(u32()), indexCount = Int(u32()), clearanceCount = Int(u32())
guard vertexCount == 13_380,indexCount == 80_268,clearanceCount == 0 else { reject("Unexpected pinned body topology") }
var points: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = []
for _ in 0..<vertexCount { points.append(SIMD3(f32(),f32(),f32())); normals.append(SIMD3(f32(),f32(),f32())) }
var indices: [UInt16] = []
for _ in 0..<indexCount {
  let value = data.withUnsafeBytes { UInt16(littleEndian: $0.loadUnaligned(fromByteOffset: offset,as: UInt16.self)) }
  offset += 2; guard value < vertexCount else { reject("Invalid pinned index") }; indices.append(value)
}
let bodyTexture = NSImage(size: NSSize(width: 128,height: 256),flipped: false) { rect in
  NSColor(calibratedRed: 0.62,green: 0.67,blue: 0.71,alpha: 1).setFill(); rect.fill()
  NSColor(calibratedWhite: 0.18,alpha: 1).setFill(); NSRect(x: 0,y: 85,width: 128,height: 48).fill()
  NSColor(calibratedWhite: 0.75,alpha: 1).setStroke()
  for y in stride(from: 0,to: 256,by: 16) {
    let line = NSBezierPath(); line.move(to: NSPoint(x: 0,y: y)); line.line(to: NSPoint(x: 128,y: y)); line.stroke()
  }
  return true
}
func png(_ image: NSImage) throws -> Data {
  guard let tiff = image.tiffRepresentation,let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png,properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
  return png
}
let textureURL = output.appendingPathComponent("synthetic-body-texture.png")
try png(bodyTexture).write(to: textureURL)
func export(_ name: String,_ geometry: SCNGeometry) throws {
  let material = SCNMaterial(); material.diffuse.contents = textureURL; material.roughness.contents = 0.85
  geometry.materials = [material]
  let scene = SCNScene(); scene.rootNode.addChildNode(SCNNode(geometry: geometry))
  let destination = output.appendingPathComponent(name+".usdz")
  guard scene.write(to: destination,options: nil,delegate: nil,progressHandler: nil) else { reject("USDZ export failed: "+name) }
  let reopened = try SCNScene(url: destination)
  guard !reopened.rootNode.childNodes.isEmpty else { reject("Empty exported scene") }
  print("Exported \(name): native USDZ, meters, authored nonpersonal texture")
}
for (name,scale) in [("synthetic-avatar-a",SIMD3<Float>(1,1,1)),("synthetic-avatar-b",SIMD3<Float>(1.13,1.06,1.10))] {
  let vertices = points.map { p -> SCNVector3 in let v = p*scale; return SCNVector3(v.x,v.y,v.z) }
  let normal = normals.map { p -> SCNVector3 in let n = simd_normalize(p/scale); return SCNVector3(n.x,n.y,n.z) }
  let uv = points.map { CGPoint(x: Double(($0.x+0.7)/1.4),y: Double($0.y/1.8)) }
  let geometry = SCNGeometry(sources: [.init(vertices: vertices),.init(normals: normal),.init(textureCoordinates: uv)],
    elements: [SCNGeometryElement(indices: indices,primitiveType: .triangles)])
  try export(name,geometry)
}
let box = SCNBox(width: 0.45,height: 1.8,length: 0.25,chamferRadius: 0.02)
box.widthSegmentCount = 8; box.heightSegmentCount = 8; box.lengthSegmentCount = 8
try export("unsupported-pose",box)
for coral in [false,true] {
  let size = NSSize(width: 720,height: 900)
  let outline = [NSPoint(x: 0.42,y: 0.12),NSPoint(x: 0.20,y: 0.18),NSPoint(x: 0.04,y: 0.34),NSPoint(x: 0.15,y: 0.47),
    NSPoint(x: 0.28,y: 0.37),NSPoint(x: 0.25,y: 0.88),NSPoint(x: 0.50,y: 0.90),NSPoint(x: 0.75,y: 0.88),NSPoint(x: 0.72,y: 0.37),
    NSPoint(x: 0.85,y: 0.47),NSPoint(x: 0.96,y: 0.34),NSPoint(x: 0.80,y: 0.18),NSPoint(x: 0.58,y: 0.12)]
  let image = NSImage(size: size,flipped: true) { _ in
    let path = NSBezierPath()
    func pixel(_ point: NSPoint) -> NSPoint { NSPoint(x: point.x*size.width,y: point.y*size.height) }
    path.move(to: pixel(outline[0])); for point in outline.dropFirst() { path.line(to: pixel(point)) }
    path.curve(to: pixel(outline[0]),controlPoint1: pixel(NSPoint(x: 0.58,y: 0.25)),controlPoint2: pixel(NSPoint(x: 0.42,y: 0.25))); path.close()
    (coral ? NSColor(calibratedRed: 0.68,green: 0.19,blue: 0.18,alpha: 1) : NSColor(calibratedRed: 0.04,green: 0.48,blue: 0.51,alpha: 1)).setFill(); path.fill()
    NSGraphicsContext.saveGraphicsState(); path.addClip()
    NSColor(calibratedRed: 0.97,green: 0.73,blue: 0.28,alpha: 1).setFill(); NSRect(x: 0,y: 290,width: 720,height: 34).fill()
    NSColor(calibratedRed: 0.94,green: 0.96,blue: 0.91,alpha: 1).setFill(); NSRect(x: 0,y: 335,width: 720,height: 12).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor(calibratedWhite: 0.1,alpha: 0.35).setStroke(); path.lineWidth = 3; path.stroke()
    return true
  }
  let name = coral ? "synthetic-shirt-coral.png" : "synthetic-shirt.png"
  try png(image).write(to: output.appendingPathComponent(name))
  print("Authored \(name); ground-truth contour observations are NOT native optical recognition")
}
print("CC0-derived/authored functional fixtures only. No photos, body measurements, or camera capture were used.")
print("Native USDZ packaging may include nondeterministic metadata; compare admitted geometry, not regenerated archive bytes.")
