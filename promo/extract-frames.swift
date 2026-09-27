import AVFoundation
import AppKit
import Foundation

guard CommandLine.arguments.count >= 4 else {
    fatalError("usage: extract-frames.swift VIDEO OUTPUT_DIR SECOND...")
}
let videoURL = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let generator = AVAssetImageGenerator(asset: AVURLAsset(url: videoURL))
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero

for value in CommandLine.arguments.dropFirst(3) {
    guard let seconds = Double(value) else { continue }
    var actual = CMTime.invalid
    let image = try generator.copyCGImage(at: CMTime(seconds: seconds,
                                                     preferredTimescale: 600),
                                          actualTime: &actual)
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let data = bitmap.representation(using: .png, properties: [:]) else { continue }
    let name = String(format: "frame-%06.2f.png", seconds)
    try data.write(to: output.appendingPathComponent(name))
}
