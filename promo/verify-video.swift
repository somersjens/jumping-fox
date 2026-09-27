import AVFoundation
import Foundation

enum VerifyError: Error { case missingVideo, readerFailed(String), noFrames }

for path in CommandLine.arguments.dropFirst() {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    guard let videoTrack = asset.tracks(withMediaType: .video).first else {
        throw VerifyError.missingVideo
    }
    let audioTrack = asset.tracks(withMediaType: .audio).first

    let reader = try AVAssetReader(asset: asset)
    // Read the encoded samples directly. This validates the complete media
    // timeline without asking VideoToolbox to hold two full-resolution pixel
    // decoders during back-to-back QA.
    let videoOutput = AVAssetReaderTrackOutput(track: videoTrack,
                                               outputSettings: nil)
    let audioOutput = audioTrack.map {
        AVAssetReaderTrackOutput(track: $0,
                                 outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
    }
    reader.add(videoOutput)
    if let audioOutput { reader.add(audioOutput) }
    guard reader.startReading() else {
        throw VerifyError.readerFailed(reader.error?.localizedDescription ?? "could not start")
    }

    var videoSamples = 0
    var audioSamples = 0
    var lastVideoTime = CMTime.zero
    var lastVideoEnd = CMTime.zero
    var maximumVideoGapSeconds: Double = 0
    var previousVideoTime: CMTime?
    while let sample = videoOutput.copyNextSampleBuffer() {
        videoSamples += 1
        lastVideoTime = CMSampleBufferGetPresentationTimeStamp(sample)
        lastVideoEnd = CMTimeAdd(lastVideoTime, CMSampleBufferGetDuration(sample))
        if let previousVideoTime {
            let gap = CMTimeGetSeconds(CMTimeSubtract(lastVideoTime, previousVideoTime))
            if gap.isFinite { maximumVideoGapSeconds = max(maximumVideoGapSeconds, gap) }
        }
        previousVideoTime = lastVideoTime
    }
    while audioOutput?.copyNextSampleBuffer() != nil { audioSamples += 1 }

    guard reader.status == .completed else {
        throw VerifyError.readerFailed(reader.error?.localizedDescription ?? "status \(reader.status.rawValue)")
    }
    guard videoSamples > 0 else { throw VerifyError.noFrames }
    let rect = CGRect(origin: .zero, size: videoTrack.naturalSize)
        .applying(videoTrack.preferredTransform)
    print(String(format: "%@: decoded %d video + %d audio samples, last frame %.3fs–%.3fs, max gap %.3fs, %.0f×%.0f",
                 path, videoSamples, audioSamples, CMTimeGetSeconds(lastVideoTime),
                 CMTimeGetSeconds(lastVideoEnd), maximumVideoGapSeconds,
                 abs(rect.width), abs(rect.height)))
}
