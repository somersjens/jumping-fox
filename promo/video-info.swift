import AVFoundation
import Foundation

for path in CommandLine.arguments.dropFirst() {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let duration = CMTimeGetSeconds(asset.duration)
    guard let track = asset.tracks(withMediaType: .video).first else {
        print("\(path): no video track")
        continue
    }
    let rect = CGRect(origin: .zero, size: track.naturalSize).applying(track.preferredTransform)
    let fps = track.nominalFrameRate
    let videoStart = CMTimeGetSeconds(track.timeRange.start)
    let videoDuration = CMTimeGetSeconds(track.timeRange.duration)
    let audio = !asset.tracks(withMediaType: .audio).isEmpty
    print(String(format: "%@: %.3fs (video %.3fs+%.3fs) %.0fx%.0f %.3ffps audio=%@ transform=[%.2f %.2f %.2f %.2f %.2f %.2f]",
                 path, duration, videoStart, videoDuration, abs(rect.width), abs(rect.height), fps,
                 audio ? "yes" : "no",
                 track.preferredTransform.a, track.preferredTransform.b,
                 track.preferredTransform.c, track.preferredTransform.d,
                 track.preferredTransform.tx, track.preferredTransform.ty))
}
