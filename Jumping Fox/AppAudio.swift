//
//  AppAudio.swift
//  Jumping Fox
//
//  All of the app's sound in one place:
//   - looping background music while a game is being played,
//   - the correct / wrong answer sound effects,
//   - the sums read aloud in every app language with a system voice, and
//   - small Apple-native tap sounds for the menus.
//
//  The start/pause card cycles through all audio, music/effects without spoken
//  sums, and fully muted. The middle option is offered only when the device has
//  a spoken-math voice for the language selected inside the app.
//

import Foundation
import Combine
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

enum AppAudioMode: String {
    case all
    case musicAndEffects
    case off
}

final class AppAudio: NSObject, ObservableObject {
    static let shared = AppAudio()

    /// Persisted audio level. Publishing the mode also refreshes the icon on the
    /// start/pause card.
    @Published private(set) var mode: AppAudioMode {
        didSet {
            guard oldValue != mode else { return }
            GameSettings.audioMode = mode
            if mode == .off {
                synthesizer.stopSpeaking(at: .immediate)
                stopMusic()
            } else if oldValue == .off {
                startMusic()   // resume the loop wherever the player is
            } else if mode == .musicAndEffects {
                synthesizer.stopSpeaking(at: .immediate)
            }
            if mode == .all {
                prewarmSpeechIfNeeded()
            }
        }
    }

    /// Music and effects remain active in both audible modes.
    var isEnabled: Bool { mode != .off }

    /// True only when both localized math wording and a matching installed
    /// system voice exist for the language currently selected in the app.
    var isSpokenMathAvailable: Bool {
        let languageCode = LanguageManager.shared.effective.code
        return SpokenMath.lexicons[languageCode] != nil
            && voicesByLanguage[languageCode] != nil
    }

    var areSpokenSumsEnabled: Bool {
        mode == .all && isSpokenMathAvailable
    }

    // MARK: Players

    private var musicPlayer: AVAudioPlayer?
    private let synthesizer = AVSpeechSynthesizer()

    /// Sound effects play through one long-lived `AVAudioEngine` instead of a
    /// pool of `AVAudioPlayer`s. The render graph stays up for the whole
    /// session, so firing an effect is just "schedule a preloaded PCM buffer on
    /// a node" — no per-play decode, no audio-session touch and no graph rebuild
    /// to land in the same frame as SpriteKit. Because the graph never tears
    /// down, a speech start or an audio-route change can no longer stall them.
    private let engine = AVAudioEngine()
    /// One player node per effect, kept in its always-on "playing" state so a
    /// trigger is a single cheap `scheduleBuffer(.interrupts)` on the node.
    private var effectNodes: [String: AVAudioPlayerNode] = [:]
    /// Preloaded, lead-trimmed PCM buffer per effect, ready to schedule.
    private var effectBuffers: [String: AVAudioPCMBuffer] = [:]

    /// The catalog of one-shot sound effects. The per-file `volume` values were
    /// measured (each file's RMS) and chosen so every effect lands at the same
    /// loudness as the "return to menu" trophy sound (~-38 dBFS) — the level
    /// that felt right — rather than each raw file playing at its own recorded
    /// level. `key` is what the `play…` methods reference.
    private struct Effect {
        let key: String
        let file: String
        let ext: String
        let volume: Float
        /// Seconds of leading silence in the file, skipped at playback so the
        /// sound fires immediately (measured per file; no re-encoding needed).
        let lead: TimeInterval
    }
    // Short effects are shipped as uncompressed CAF/PCM: unlike MP3 they need no
    // runtime decode, so re-triggering one (rewind to `lead` + `play`) during a
    // busy frame costs no CPU and can't contend for the shared audio decoder.
    // The four `wav` files were already PCM. `volume`/`lead` are unchanged: the
    // conversion preserved each file's sample rate, channels and timing exactly.
    private static let effects: [Effect] = [
        Effect(key: "correct",       file: "sfx_correct",        ext: "caf", volume: 0.16, lead: 0.0),
        Effect(key: "wrong",         file: "sfx_wrong",          ext: "caf", volume: 0.11, lead: 0.065),
        Effect(key: "triplerPickup", file: "sfx_tripler_pickup", ext: "caf", volume: 0.18, lead: 0.0),
        Effect(key: "triplerUsed",   file: "sfx_tripler_used",   ext: "caf", volume: 0.15, lead: 0.0),
        Effect(key: "life",          file: "sfx_life",           ext: "caf", volume: 0.15, lead: 0.155),
        // Deliberately louder than the rest — the source is boosted and it plays
        // above the pack, because at the matched level it was barely audible.
        Effect(key: "heartArrive",   file: "sfx_heart_arrive",   ext: "wav", volume: 0.50, lead: 0.0),
        Effect(key: "minus",         file: "sfx_minus_coin",     ext: "caf", volume: 0.24, lead: 0.045),
        Effect(key: "shootingStar",  file: "sfx_shooting_star",  ext: "caf", volume: 0.31, lead: 0.045),
        Effect(key: "streak",        file: "sfx_streak",         ext: "caf", volume: 0.16, lead: 0.225),
        Effect(key: "levelComplete", file: "sfx_level_complete", ext: "caf", volume: 0.10, lead: 0.010),
        Effect(key: "characterUnlock", file: "sfx_character_unlock", ext: "caf", volume: 0.12, lead: 0.050),
        Effect(key: "jump",          file: "sfx_jump",           ext: "wav", volume: 0.20, lead: 0.015),
        Effect(key: "trophyMenu",    file: "sfx_trophy_menu",    ext: "caf", volume: 1.0,  lead: 0.065),
        Effect(key: "trophyTotal",   file: "sfx_trophy_total",   ext: "wav", volume: 0.08, lead: 0.015),
        Effect(key: "select",        file: "sfx_select",         ext: "wav", volume: 0.17, lead: 0.0),
        // Toggle switches in the menu (helper mode, etc.).
        Effect(key: "switchOn",      file: "sfx_switch_on",      ext: "caf", volume: 0.89, lead: 0.200),
        Effect(key: "switchOff",     file: "sfx_switch_off",     ext: "caf", volume: 1.0,  lead: 0.170)
    ]

    /// True while a level is actually being played (not the menu, the intro/
    /// pause card or the result screen). The music loops everywhere, but plays
    /// louder here; the sums are only spoken while this is true.
    private(set) var isGameplayActive = false

    private var sessionConfigured = false
    private var sessionActive = false
    /// The music loops continuously: softly in the background on the menus and
    /// cards, a little louder during play, and briefly ducked while a sum is
    /// read so the words stay clearly audible over it.
    private let menuMusicVolume: Float = 0.10
    private let gameMusicVolume: Float = 0.30
    private let duckedMusicVolume: Float = 0.05

    /// The volume the music should currently sit at, given where the player is.
    private var currentMusicTarget: Float { isGameplayActive ? gameMusicVolume : menuMusicVolume }

    /// One-time, off-the-main-thread setup so nothing has to be allocated,
    /// decoded or session-activated during play — that first-touch work was
    /// what stuttered the game the first time a sound played.
    private var isPrepared = false
    private var didPrewarmSpeech = false
    private let prepareQueue = DispatchQueue(label: "com.jumpingfox.audio.prepare", qos: .userInitiated)

    // MARK: Voices

    /// Best installed voice per spoken-math language, resolved once. Voice
    /// availability differs by OS version and by voices downloaded in Settings.
    private lazy var voicesByLanguage: [String: AVSpeechSynthesisVoice] = Self.bestVoicesByLanguage()

    private override init() {
        self.mode = GameSettings.audioMode
        super.init()
        synthesizer.delegate = self
        // Speak through the app's own (already-active) audio session rather than
        // letting the synthesizer manage a private one — that private-session
        // churn is what let a spoken sum disturb the effects' audio route.
        synthesizer.usesApplicationAudioSession = true
        registerForInterruptions()
    }

    /// Advances the intro-card button. Languages without spoken math skip the
    /// middle state, so the same control behaves as a normal two-state switch.
    func cycleMode() {
        if isSpokenMathAvailable {
            switch mode {
            case .all:             mode = .musicAndEffects
            case .musicAndEffects: mode = .off
            case .off:             mode = .all
            }
        } else {
            mode = isEnabled ? .off : .all
        }
    }

    // MARK: - Preparation (called once, up front)

    /// Loads and prepares every player (and warms the speech engine) on a
    /// background queue. Cheap to call repeatedly; only the first call works.
    /// The heavy, blocking bits — file decode, `prepareToPlay`, session
    /// activation — happen here, at a calm moment, not mid-game.
    func prepare() {
        guard !isPrepared else { return }
        isPrepared = true
        prepareQueue.async { [weak self] in
            guard let self else { return }
            let music = Self.makePlayer(named: "music_background", loops: -1, volume: 0)
            // Decode + lead-trim every effect into a ready-to-schedule PCM buffer
            // here, off the main thread, so play time does no file work at all.
            var buffers: [String: AVAudioPCMBuffer] = [:]
            for effect in Self.effects {
                buffers[effect.key] = Self.makeBuffer(named: effect.file, ext: effect.ext,
                                                      trimLeading: effect.lead)
            }
            DispatchQueue.main.async {
                if self.musicPlayer == nil { self.musicPlayer = music }
                self.installEffectBuffers(buffers)
                // Only touch the audio session (and warm speech) when sound is
                // on, so a muted app never interrupts the user's own audio.
                if self.isEnabled {
                    self.activateSession()
                    self.prewarmSpeechIfNeeded()
                }
            }
        }
    }

    /// Attaches one player node per effect and wires it to the engine's mixer at
    /// the buffer's own format (the mixer resamples as needed, so effects keep
    /// their native rates). Runs once, on the main thread, after the background
    /// decode; the engine itself is only started when sound is on.
    private func installEffectBuffers(_ buffers: [String: AVAudioPCMBuffer]) {
        for effect in Self.effects where effectBuffers[effect.key] == nil {
            guard let buffer = buffers[effect.key] else { continue }
            effectBuffers[effect.key] = buffer
            let node = AVAudioPlayerNode()
            node.volume = effect.volume
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: buffer.format)
            effectNodes[effect.key] = node
        }
        // The session can go active before this background decode finishes — the
        // tutorial starts gameplay immediately, with no start card, so
        // `activateSession()` runs while `effectNodes` is still empty and
        // `startEngineIfNeeded()` skips (nothing to play). Once activated,
        // `activateSession()` short-circuits and never retries, so the engine
        // would stay down and every effect would be silent. Now that the nodes
        // exist, bring the engine up here.
        if sessionActive { startEngineIfNeeded() }
    }

    /// Builds a fully prepared player. Runs the decode/`prepareToPlay` cost on
    /// whatever (background) queue calls it.
    private static func makePlayer(named name: String, ext: String = "mp3",
                                   loops: Int, volume: Float) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.numberOfLoops = loops
        player.volume = volume
        player.prepareToPlay()
        return player
    }

    /// Decodes a sound file into a PCM buffer, dropping `trimLeading` seconds of
    /// leading silence so a scheduled buffer sounds immediately. (The old players
    /// did this by seeking on every play; baking it into the buffer once makes
    /// each trigger free.) Runs on whatever background queue calls it.
    private static func makeBuffer(named name: String, ext: String,
                                   trimLeading: TimeInterval) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let skip = AVAudioFramePosition((trimLeading * format.sampleRate).rounded())
        let start = min(max(0, skip), file.length)
        file.framePosition = start
        let frames = AVAudioFrameCount(file.length - start)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              (try? file.read(into: buffer)) != nil else { return nil }
        return buffer
    }

    /// Starts the effects engine (once) and puts every effect node into its
    /// always-on "playing" state, so a later trigger is a single scheduleBuffer
    /// with nothing to spin up. Requires the session active; a no-op when sound
    /// is off, the engine is already running, or the nodes aren't attached yet.
    private func startEngineIfNeeded() {
        guard isEnabled, !engine.isRunning, !effectNodes.isEmpty else { return }
        engine.prepare()
        guard (try? engine.start()) != nil else { return }
        for node in effectNodes.values { node.play() }
    }

    /// Stops the effect nodes and the engine (used when going silent or
    /// backgrounding); the attached graph is kept for a later restart.
    private func stopEngine() {
        guard engine.isRunning else { return }
        for node in effectNodes.values { node.stop() }
        engine.stop()
    }

    /// Speaks a silent utterance so the very first real sum doesn't pay the
    /// one-off cost of spinning up the speech engine and loading the voice.
    private func prewarmSpeechIfNeeded() {
        let languageCode = LanguageManager.shared.effective.code
        guard mode == .all,
              !didPrewarmSpeech,
              SpokenMath.lexicons[languageCode] != nil,
              let voice = voicesByLanguage[languageCode] else { return }
        didPrewarmSpeech = true
        let warmup = AVSpeechUtterance(string: " ")
        warmup.voice = voice
        warmup.volume = 0
        synthesizer.speak(warmup)
    }

    // MARK: - Audio session

    private func configureSessionIfNeeded() {
        guard !sessionConfigured else { return }
        let session = AVAudioSession.sharedInstance()
        // `.playback` keeps the game audible even with the ring/silent switch
        // set to silent — expected for a game the child is actively playing,
        // and the single in-app switch is the real mute control.
        try? session.setCategory(.playback, mode: .default, options: [])
        sessionConfigured = true
    }

    private func activateSession() {
        guard !sessionActive else { return }   // syscall only once, never mid-game
        configureSessionIfNeeded()
        try? AVAudioSession.sharedInstance().setActive(true)
        sessionActive = true
        startEngineIfNeeded()                  // bring the effects graph up with it
    }

    private func deactivateSession() {
        guard sessionActive else { return }
        stopEngine()
        // Let any paused apps (music, podcasts) resume once we go quiet.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        sessionActive = false
    }

    // MARK: - Gameplay lifecycle

    /// Called by the game view as the play field becomes (in)active. The music
    /// keeps looping either way; this only raises it for play and lowers it
    /// back to the soft menu level afterwards, and reads the current sum aloud
    /// on the transition into play.
    func setGameplayActive(_ active: Bool, questionText: String?) {
        let wasActive = isGameplayActive
        isGameplayActive = active
        if active {
            guard isEnabled else { return }
            startMusic()
            setMusicVolume(gameMusicVolume)
            // Read the sum the player is looking at the moment play begins.
            if !wasActive, let questionText { speakQuestion(questionText) }
        } else {
            synthesizer.stopSpeaking(at: .immediate)
            setMusicVolume(menuMusicVolume) // keep the loop, just soften it
        }
    }

    // MARK: - Background music

    /// Starts (or resumes) the endless background loop at the volume that suits
    /// the current screen. Safe to call repeatedly.
    func startMusic() {
        guard isEnabled else { return }
        activateSession()
        // Normally already loaded by `prepare()`; fall back to a synchronous
        // load only if music is somehow needed before preparation finished.
        if musicPlayer == nil {
            musicPlayer = Self.makePlayer(named: "music_background", loops: -1, volume: 0)
        }
        guard let player = musicPlayer else { return }
        if !player.isPlaying {
            player.volume = 0
            player.play()
            player.setVolume(currentMusicTarget, fadeDuration: 0.6) // gentle fade-in
        } else {
            setMusicVolume(currentMusicTarget)
        }
    }

    private func setMusicVolume(_ volume: Float, fade: TimeInterval = 0.4) {
        musicPlayer?.setVolume(volume, fadeDuration: fade)
    }

    /// Fades the music out and stops it — used only when sound is switched off
    /// (or paused for backgrounding, via `pause`).
    private func stopMusic() {
        guard let player = musicPlayer, player.isPlaying else {
            musicPlayer?.stop()
            deactivateSession()
            return
        }
        player.setVolume(0, fadeDuration: 0.35)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, !self.isEnabled else { return }
            self.musicPlayer?.stop()
            self.musicPlayer?.currentTime = 0
            self.deactivateSession()
        }
    }

    /// Lower / restore the music around a spoken sum (speech only happens in
    /// play, so it restores to the gameplay level).
    private func duckMusic(_ ducked: Bool) {
        guard let player = musicPlayer, player.isPlaying else { return }
        player.setVolume(ducked ? duckedMusicVolume : currentMusicTarget, fadeDuration: 0.18)
    }

    // MARK: - Sound effects

    // Answers.
    func playCorrect()       { playEffect("correct") }
    func playWrong()         { playEffect("wrong") }
    func playJump()          { playEffect("jump") }          // bounce off a plain stone
    // Pickups.
    func playTriplerPickup() { playEffect("triplerPickup") } // ×3 coin collected
    func playLife()          { playEffect("life") }          // heart collected
    func playHeartArrive()   { playEffect("heartArrive") }   // half heart lands in the HUD
    func playMinus()         { playEffect("minus") }         // −1 hazard collected
    func playShootingStar()  { playEffect("shootingStar") }  // star pickup collected
    // Milestones.
    func playTriplerUsed()     { playEffect("triplerUsed") }     // ×3 spent on a correct answer
    func playStreak()          { playEffect("streak") }          // 5-in-a-row streak turns on
    func playLevelComplete()   { playEffect("levelComplete") }   // level finished
    func playCharacterUnlock() { playEffect("characterUnlock") } // new character earned
    func playTrophyMenu()      { playEffect("trophyMenu") }      // card counts up on return to menu
    func playTrophyTotal()     { playEffect("trophyTotal") }     // grand total ticks up at the top
    // Menu controls.
    /// Small select sound for menu navigation (the supplied `select.wav`).
    func playMenuTap()         { playEffect("select") }
    /// Toggle switches: on / off variants.
    func playSwitch(on: Bool)  { playEffect(on ? "switchOn" : "switchOff") }

    private func playEffect(_ key: String) {
        guard isEnabled else { return }
        activateSession()
        // Preloaded by `prepare()`. If a sound is somehow needed before that
        // finished (rare — play happens well after launch) it's simply skipped;
        // no synchronous file work is ever done on this hot path.
        guard let node = effectNodes[key], let buffer = effectBuffers[key] else { return }
        // The node is already running (see `startEngineIfNeeded`); `.interrupts`
        // restarts it from the top with nothing to allocate — the whole trigger
        // is one buffer schedule on the audio render thread, invisible to the
        // frame. The lead trim and volume are already baked in at load time.
        if !node.isPlaying { node.play() }
        node.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
    }

    // MARK: - Spoken sums

    /// Bumped on every request so a superseded (debounced) one can bow out.
    private var speechRequestToken = 0
    /// How long to wait after a new sum appears before speaking it. This keeps
    /// the synthesizer's start-up work out of the exact frames where the jump
    /// lands and SpriteKit rebuilds the answer board — the collision that made
    /// the game stutter — and debounces fast consecutive answers to the latest.
    private let speechStartDelay: TimeInterval = 0.3

    /// Requests that a sum such as "3 + 4 = ?" be read in the interface
    /// language. No-op unless that language has both localized math wording and
    /// an installed system voice. Speech is deferred (see `speechStartDelay`).
    func speakQuestion(_ prompt: String) {
        guard mode == .all, isGameplayActive else { return }
        let languageCode = LanguageManager.shared.effective.code
        guard let voice = voicesByLanguage[languageCode] else { return }
        guard let text = Self.spokenText(for: prompt, languageCode: languageCode) else { return }
        guard !text.isEmpty else { return }

        speechRequestToken += 1
        let token = speechRequestToken
        DispatchQueue.main.asyncAfter(deadline: .now() + speechStartDelay) { [weak self] in
            guard let self, token == self.speechRequestToken else { return } // superseded
            self.performSpeak(text, voice: voice)
        }
    }

    private func performSpeak(_ text: String, voice: AVSpeechSynthesisVoice) {
        guard mode == .all, isGameplayActive else { return }
        // Never interrupt/reset the synthesizer in the hot path — stopSpeaking
        // is a documented source of hitches. If a previous sum is still being
        // read (the child answered very fast), just let it finish and skip this
        // one rather than cutting it off.
        guard !synthesizer.isSpeaking else { return }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        // Keep the rate near the natural default — stretching a compact voice
        // out slowly makes it sound *more* robotic, not less. A hair under
        // default with a slightly brighter pitch stays clear and friendly.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        utterance.pitchMultiplier = 1.05
        utterance.postUtteranceDelay = 0.05
        duckMusic(true)
        synthesizer.speak(utterance)
    }

    /// Turns a written sum into speech — just the essential sum, without a
    /// sentence such as “what is”. Kept as an English-compatible overload for
    /// existing callers and focused unit tests.
    ///
    /// Handles every sum the game produces:
    ///   "3 + 4 = ?"        -> "3 plus 4"
    ///   "12 − 5 = ?"       -> "12 minus 5"
    ///   "6 × 7 = ?"        -> "6 times 7"
    ///   "3/4 × 8 = ?"      -> "3 over 4 times 8"
    ///   "1/4 + 1/4 = ?"    -> "1 over 4 plus 1 over 4"
    ///   "25% × 40 = ?"     -> "25 percent of 40"
    ///   "1/2 = ?"          -> "1 over 2"
    ///   "1/2 = ?/4"        -> "1 over 2 is how many over 4"  (unknown on right)
    static func spokenText(for prompt: String) -> String {
        SpokenMath.text(for: prompt, languageCode: "en") ?? ""
    }

    static func spokenText(for prompt: String, languageCode: String) -> String? {
        SpokenMath.text(for: prompt, languageCode: languageCode)
    }

    /// Retained for callers that specifically need the legacy English choice.
    static func bestEnglishVoice() -> AVSpeechSynthesisVoice? {
        bestVoicesByLanguage()["en"] ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    /// Picks the clearest installed voice for each supported language. Apple
    /// identifies Norwegian Bokmål as `nb`, while the app uses the broader
    /// language code `no`, so that one is mapped explicitly. Dutch is pinned
    /// to the Netherlands locale so a higher-quality Belgian voice cannot win.
    private static func bestVoicesByLanguage() -> [String: AVSpeechSynthesisVoice] {
        let novelty: Set<String> = ["Albert", "Bad News", "Bahh", "Bells", "Boing",
                                    "Bubbles", "Cellos", "Wobble", "Fred", "Good News",
                                    "Jester", "Organ", "Superstar", "Trinoids",
                                    "Whisper", "Zarvox", "Junior", "Ralph", "Kathy"]

        func score(_ v: AVSpeechSynthesisVoice) -> Int {
            var s = 0
            switch v.quality {
            case .premium:  s += 300
            case .enhanced: s += 200
            default:        s += 100
            }
            return s
        }

        let installed = AVSpeechSynthesisVoice.speechVoices()
            .filter { !novelty.contains($0.name) }
        var result: [String: AVSpeechSynthesisVoice] = [:]
        for languageCode in SpokenMath.lexicons.keys {
            let voiceCode = languageCode == "no" ? "nb" : languageCode
            let candidates = installed.filter {
                $0.language.split(separator: "-").first.map(String.init) == voiceCode
            }
            let localeCandidates: [AVSpeechSynthesisVoice]
            if languageCode == "nl" {
                localeCandidates = candidates.filter { $0.language == "nl-NL" }
            } else {
                localeCandidates = candidates
            }
            if let best = localeCandidates.max(by: { score($0) < score($1) }) {
                result[languageCode] = best
            }
        }
        return result
    }

    // MARK: - Interruptions & backgrounding

    private func registerForInterruptions() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(handleInterruption(_:)),
                           name: AVAudioSession.interruptionNotification, object: nil)
        // A route change (headphones plugged/unplugged, etc.) stops the engine;
        // this brings it back so effects keep working afterwards.
        center.addObserver(self, selector: #selector(handleEngineConfigurationChange),
                           name: .AVAudioEngineConfigurationChange, object: engine)
#if canImport(UIKit)
        center.addObserver(self, selector: #selector(appWillResignActive),
                           name: UIApplication.willResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(appDidBecomeActive),
                           name: UIApplication.didBecomeActiveNotification, object: nil)
#endif
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            musicPlayer?.pause()
            synthesizer.stopSpeaking(at: .immediate)
            // The system deactivates our session and stops the engine; mirror
            // that so `ended` can cleanly reactivate and bring the effects back.
            stopEngine()
        case .ended:
            if let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt,
               AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume) {
                sessionActive = false   // force a real reactivation of session + engine
                startMusic()
            }
        @unknown default:
            break
        }
    }

    /// The route/config changed and stopped the engine; restart it in place.
    @objc private func handleEngineConfigurationChange() {
        DispatchQueue.main.async { [weak self] in self?.startEngineIfNeeded() }
    }

    @objc private func appWillResignActive() {
        musicPlayer?.pause()
        synthesizer.stopSpeaking(at: .immediate)
        stopEngine()
    }

    @objc private func appDidBecomeActive() {
        // The loop plays app-wide, so resume it wherever the player is, and
        // bring the effects engine back up (it was stopped on resigning active).
        startMusic()
        startEngineIfNeeded()
    }
}

// MARK: - Speech delegate (music ducking)

extension AppAudio: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        duckMusic(false)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        duckMusic(false)
    }
}
