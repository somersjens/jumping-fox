import AVFoundation
import Foundation

enum MasterError: Error, CustomStringConvertible {
    case usage, missingVideo, cannotCreateTrack, cannotCreateExporter, exportFailed(String)
    var description: String {
        switch self {
        case .usage:
            return "usage: master-video.swift INPUT OUTPUT WIDTH HEIGHT START DURATION EVENTS AUDIO_DELAY"
        case .missingVideo: return "input has no video track"
        case .cannotCreateTrack: return "could not create a composition track"
        case .cannotCreateExporter: return "could not create an AVAssetExportSession"
        case .exportFailed(let message): return "export failed: \(message)"
        }
    }
}

guard CommandLine.arguments.count == 9,
      let width = Double(CommandLine.arguments[3]),
      let height = Double(CommandLine.arguments[4]),
      let startSeconds = Double(CommandLine.arguments[5]),
      let durationSeconds = Double(CommandLine.arguments[6]),
      let audioDelay = Double(CommandLine.arguments[8]) else {
    throw MasterError.usage
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let eventsURL = URL(fileURLWithPath: CommandLine.arguments[7])
let targetSize = CGSize(width: width, height: height)
let outputDuration = CMTime(seconds: durationSeconds, preferredTimescale: 600)
struct RecordedEvent {
    let time: Double
    let name: String
}

let recordedEvents = try String(contentsOf: eventsURL, encoding: .utf8)
    .split(whereSeparator: { $0.isNewline })
    .compactMap { line -> RecordedEvent? in
        let fields = line.split(separator: "\t", maxSplits: 1).map(String.init)
        guard fields.count == 2, let time = Double(fields[0]) else { return nil }
        return RecordedEvent(time: time, name: fields[1])
    }
let menuSelections = recordedEvents.filter {
    $0.name.hasPrefix("menu_") && $0.name != "menu_loop_complete"
}
let menuLoopComplete = recordedEvents.first { $0.name == "menu_loop_complete" }
let normalizeMenuSlots = menuSelections.count > 1 && menuLoopComplete != nil
let menuSlotDuration = durationSeconds / Double(max(1, menuSelections.count))
// Skip the first two recorded frames at the cut-in — simctl recordVideo often
// emits an incomplete/white sample exactly when gameplay is unfrozen.
let sourceStart = CMTime(seconds: startSeconds + 2.0 / 30.0, preferredTimescale: 600)

let source = AVURLAsset(url: inputURL)
guard let sourceVideo = source.tracks(withMediaType: .video).first else {
    throw MasterError.missingVideo
}
let composition = AVMutableComposition()
guard let videoTrack = composition.addMutableTrack(withMediaType: .video,
                                                   preferredTrackID: kCMPersistentTrackID_Invalid) else {
    throw MasterError.cannotCreateTrack
}
var backingTrack: AVMutableCompositionTrack?
if normalizeMenuSlots, let menuLoopComplete {
    // Keep a continuous source underneath the retimed menu slices. Simulator
    // recordings use variable frame timing; this guarantees the compositor has
    // a frame for every one of the 756 output frames, including the loop tail.
    if let track = composition.addMutableTrack(withMediaType: .video,
                                               preferredTrackID: kCMPersistentTrackID_Invalid) {
        try track.insertTimeRange(CMTimeRange(start: sourceStart, duration: outputDuration),
                                  of: sourceVideo, at: .zero)
        backingTrack = track
    }
    // Use the recorder's real terminal sample for the final slice. Screen
    // recording is variable-frame-rate and may omit unchanged frames between
    // the loop-complete event and shutdown; including its terminal sample makes
    // the encoded video track itself reach the full master duration.
    let recordedTail = CMTimeGetSeconds(source.duration) - CMTimeGetSeconds(sourceStart)
    let finalBoundary = max(menuLoopComplete.time, recordedTail)
    let boundaries = menuSelections.map(\.time) + [finalBoundary]
    var outputCursor = CMTime.zero
    for index in menuSelections.indices {
        let sourceDurationSeconds = max(1.0 / 60.0, boundaries[index + 1] - boundaries[index])
        let sourceRange = CMTimeRange(
            start: CMTimeAdd(sourceStart,
                             CMTime(seconds: boundaries[index], preferredTimescale: 600)),
            duration: CMTime(seconds: sourceDurationSeconds, preferredTimescale: 600)
        )
        try videoTrack.insertTimeRange(sourceRange, of: sourceVideo, at: outputCursor)
        let insertedRange = CMTimeRange(start: outputCursor, duration: sourceRange.duration)
        let normalizedDuration = CMTime(seconds: menuSlotDuration, preferredTimescale: 600)
        videoTrack.scaleTimeRange(insertedRange, toDuration: normalizedDuration)
        outputCursor = CMTimeAdd(outputCursor, normalizedDuration)
    }
} else {
    try videoTrack.insertTimeRange(CMTimeRange(start: sourceStart, duration: outputDuration),
                                   of: sourceVideo, at: .zero)
}

let sourceSize = sourceVideo.naturalSize
let scale = max(targetSize.width / sourceSize.width,
                targetSize.height / sourceSize.height)
let x = (targetSize.width - sourceSize.width * scale) / 2
let y = (targetSize.height - sourceSize.height * scale) / 2
let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: x, ty: y)

let instruction = AVMutableVideoCompositionInstruction()
instruction.timeRange = CMTimeRange(start: .zero, duration: outputDuration)
let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
layer.setTransform(transform, at: .zero)
var layerInstructions: [AVVideoCompositionLayerInstruction] = [layer]
if let backingTrack {
    let backingLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: backingTrack)
    backingLayer.setTransform(transform, at: .zero)
    layerInstructions.append(backingLayer)
}
instruction.layerInstructions = layerInstructions

let videoComposition = AVMutableVideoComposition()
videoComposition.renderSize = targetSize
videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
videoComposition.instructions = [instruction]
videoComposition.renderScale = 1

var mixParameters: [AVMutableAudioMixInputParameters] = []

func addAudio(_ url: URL, at start: CMTime, volume: Float,
              sourceOffset: CMTime = .zero,
              durationLimit: CMTime? = nil) throws {
    let asset = AVURLAsset(url: url)
    guard let sourceTrack = asset.tracks(withMediaType: .audio).first,
          let destination = composition.addMutableTrack(withMediaType: .audio,
                                                        preferredTrackID: kCMPersistentTrackID_Invalid) else {
        return
    }
    let remaining = CMTimeSubtract(outputDuration, start)
    guard remaining > .zero else { return }
    var duration = min(CMTimeSubtract(asset.duration, sourceOffset), remaining)
    if let durationLimit { duration = min(duration, durationLimit) }
    guard duration > .zero else { return }
    try destination.insertTimeRange(CMTimeRange(start: sourceOffset, duration: duration),
                                    of: sourceTrack, at: start)
    let parameters = AVMutableAudioMixInputParameters(track: destination)
    parameters.setVolume(volume, at: start)
    mixParameters.append(parameters)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let musicURL = root.appendingPathComponent("Jumping Fox/music_background.mp3")
let music = AVURLAsset(url: musicURL)
if let musicTrack = music.tracks(withMediaType: .audio).first,
   let destination = composition.addMutableTrack(withMediaType: .audio,
                                                 preferredTrackID: kCMPersistentTrackID_Invalid) {
    var cursor = CMTime.zero
    while cursor < outputDuration {
        let segment = min(music.duration, CMTimeSubtract(outputDuration, cursor))
        try destination.insertTimeRange(CMTimeRange(start: .zero, duration: segment),
                                        of: musicTrack, at: cursor)
        cursor = CMTimeAdd(cursor, segment)
    }
    let parameters = AVMutableAudioMixInputParameters(track: destination)
    parameters.setVolume(0.20, at: .zero)
    parameters.setVolumeRamp(fromStartVolume: 0.20, toEndVolume: 0.0,
                             timeRange: CMTimeRange(start: CMTimeSubtract(outputDuration,
                                                                         CMTime(seconds: 1.2,
                                                                                preferredTimescale: 600)),
                                                    duration: CMTime(seconds: 1.2,
                                                                     preferredTimescale: 600)))
    mixParameters.append(parameters)
}

struct EventSound {
    let filename: String
    let lead: Double
    let triggerOffset: Double
}

let eventSounds: [String: EventSound] = [
    // Landing events fire on contact. In-game the jump cue is predicted
    // `jumpSoundLead` (60ms) before that, so pull stone hits onto the squash
    // rather than the already-rising hop.
    "opening_landing": EventSound(filename: "sfx_jump.caf", lead: 0, triggerOffset: -0.11),
    "opening_empty_landing": EventSound(filename: "sfx_jump.caf", lead: 0, triggerOffset: -0.11),
    "answer_15": EventSound(filename: "sfx_correct.caf", lead: 0, triggerOffset: -0.06),
    "empty_before_tripler": EventSound(filename: "sfx_jump.caf", lead: 0, triggerOffset: -0.11),
    "tripler_collected": EventSound(filename: "sfx_tripler_pickup.caf", lead: 0, triggerOffset: -0.04),
    "multiplier_landing": EventSound(filename: "sfx_jump.caf", lead: 0, triggerOffset: -0.11),
    "empty_after_tripler": EventSound(filename: "sfx_jump.caf", lead: 0, triggerOffset: -0.11),
    "star_collected": EventSound(filename: "sfx_shooting_star.caf", lead: 0, triggerOffset: -0.04),
    "star_landing": EventSound(filename: "sfx_jump.caf", lead: 0, triggerOffset: -0.11),
    "answer_56": EventSound(filename: "sfx_tripler_used.caf", lead: 0, triggerOffset: -0.06),
    // One unlock cue for the whole character showcase, on the first morph.
    "character_bunny": EventSound(filename: "sfx_character_unlock.caf", lead: 0, triggerOffset: 0),
    "bunny_landing": EventSound(filename: "sfx_jump.caf", lead: 0, triggerOffset: -0.11),
    "dog_landing": EventSound(filename: "sfx_jump.caf", lead: 0, triggerOffset: -0.11),
    "wrap_landing": EventSound(filename: "sfx_jump.caf", lead: 0, triggerOffset: -0.11),
    "bear_landing": EventSound(filename: "sfx_jump.caf", lead: 0, triggerOffset: -0.11),
    // Only one end stinger — completion_launch and final_answer fire on the
    // same frame, so a second cue sounded like an echo.
    "completion_launch": EventSound(filename: "sfx_level_complete.caf", lead: 0, triggerOffset: 0)
]

var menuSelectionIndex = 0
for event in recordedEvents {
    let eventName = event.name
    let sound = eventSounds[eventName]
        ?? (eventName.hasPrefix("menu_") && eventName != "menu_loop_complete"
            ? EventSound(filename: "sfx_select.caf", lead: 0, triggerOffset: 0)
            : nil)
    guard let sound else { continue }
    let url = root.appendingPathComponent("Jumping Fox/\(sound.filename)")
    let eventTime: Double
    if normalizeMenuSlots, eventName.hasPrefix("menu_") {
        eventTime = Double(menuSelectionIndex) * menuSlotDuration
        menuSelectionIndex += 1
    } else {
        eventTime = event.time
    }
    let at = CMTime(seconds: max(0, audioDelay + eventTime + sound.triggerOffset),
                    preferredTimescale: 600)
    let sourceOffset = CMTime(seconds: sound.lead, preferredTimescale: 600)
    try addAudio(url, at: at, volume: 0.92, sourceOffset: sourceOffset)
}

let audioMix = AVMutableAudioMix()
audioMix.inputParameters = mixParameters

try? FileManager.default.removeItem(at: outputURL)
guard let exporter = AVAssetExportSession(asset: composition,
                                          presetName: AVAssetExportPresetHighestQuality) else {
    throw MasterError.cannotCreateExporter
}
exporter.outputURL = outputURL
exporter.outputFileType = .mp4
exporter.videoComposition = videoComposition
exporter.audioMix = audioMix
exporter.shouldOptimizeForNetworkUse = true

let semaphore = DispatchSemaphore(value: 0)
exporter.exportAsynchronously { semaphore.signal() }
semaphore.wait()
guard exporter.status == .completed else {
    throw MasterError.exportFailed(exporter.error.map(String.init(describing:))
                                   ?? "status \(exporter.status.rawValue)")
}

print(String(format: "Wrote %@ — %.1fs, %.0f×%.0f, 30 fps",
             outputURL.path, durationSeconds, width, height))
