//
//  AppAudio.swift
//  Jumping Fox
//
//  All of the app's sound in one place:
//   - looping background music while a game is being played,
//   - the correct / wrong answer sound effects,
//   - the sums read aloud (English only), and
//   - small Apple-native tap sounds for the menus.
//
//  Everything is behind a single master switch (`isEnabled`), on by default,
//  toggled from the start/pause card. When it is off the app is completely
//  silent. The spoken sums are a bonus that only ever run in English; every
//  other language still gets music and the two answer sounds.
//

import Foundation
import Combine
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

final class AppAudio: NSObject, ObservableObject {
    static let shared = AppAudio()

    /// Master switch for every sound in the app. Persisted, and mirrored here
    /// as `@Published` so the toggle button can bind to it directly.
    @Published var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            GameSettings.soundEnabled = isEnabled
            if isEnabled {
                startMusic()   // resume the loop wherever the player is
            } else {
                synthesizer.stopSpeaking(at: .immediate)
                stopMusic()
            }
        }
    }

    // MARK: Players

    private var musicPlayer: AVAudioPlayer?
    private let synthesizer = AVSpeechSynthesizer()

    /// One reusable player per sound effect, keyed by `Effect.key`.
    private var effectPlayers: [String: AVAudioPlayer] = [:]

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
    private static let effects: [Effect] = [
        Effect(key: "correct",       file: "sfx_correct",        ext: "mp3", volume: 0.16, lead: 0.0),
        Effect(key: "wrong",         file: "sfx_wrong",          ext: "mp3", volume: 0.11, lead: 0.065),
        Effect(key: "triplerPickup", file: "sfx_tripler_pickup", ext: "mp3", volume: 0.18, lead: 0.0),
        Effect(key: "triplerUsed",   file: "sfx_tripler_used",   ext: "mp3", volume: 0.15, lead: 0.0),
        Effect(key: "life",          file: "sfx_life",           ext: "mp3", volume: 0.15, lead: 0.155),
        // Deliberately louder than the rest — the source is boosted and it plays
        // above the pack, because at the matched level it was barely audible.
        Effect(key: "heartArrive",   file: "sfx_heart_arrive",   ext: "wav", volume: 0.50, lead: 0.0),
        Effect(key: "minus",         file: "sfx_minus_coin",     ext: "mp3", volume: 0.24, lead: 0.045),
        Effect(key: "shootingStar",  file: "sfx_shooting_star",  ext: "mp3", volume: 0.31, lead: 0.045),
        Effect(key: "streak",        file: "sfx_streak",         ext: "mp3", volume: 0.16, lead: 0.225),
        Effect(key: "levelComplete", file: "sfx_level_complete", ext: "mp3", volume: 0.10, lead: 0.010),
        Effect(key: "characterUnlock", file: "sfx_character_unlock", ext: "mp3", volume: 0.12, lead: 0.050),
        Effect(key: "jump",          file: "sfx_jump",           ext: "wav", volume: 0.20, lead: 0.015),
        Effect(key: "trophyMenu",    file: "sfx_trophy_menu",    ext: "mp3", volume: 1.0,  lead: 0.065),
        Effect(key: "trophyTotal",   file: "sfx_trophy_total",   ext: "wav", volume: 0.08, lead: 0.015),
        Effect(key: "select",        file: "sfx_select",         ext: "wav", volume: 0.17, lead: 0.0),
        // Toggle switches in the menu (helper mode, etc.).
        Effect(key: "switchOn",      file: "sfx_switch_on",      ext: "mp3", volume: 0.89, lead: 0.200),
        Effect(key: "switchOff",     file: "sfx_switch_off",     ext: "mp3", volume: 1.0,  lead: 0.170)
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

    // MARK: Voice (English sums)

    /// The friendliest, clearest installed English voice, resolved once.
    private lazy var englishVoice: AVSpeechSynthesisVoice? = Self.bestEnglishVoice()

    private override init() {
        self.isEnabled = GameSettings.soundEnabled
        super.init()
        synthesizer.delegate = self
        registerForInterruptions()
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
            var effects: [String: AVAudioPlayer] = [:]
            for effect in Self.effects {
                effects[effect.key] = Self.makePlayer(named: effect.file, ext: effect.ext,
                                                       loops: 0, volume: effect.volume)
            }
            DispatchQueue.main.async {
                if self.musicPlayer == nil { self.musicPlayer = music }
                for (key, player) in effects where self.effectPlayers[key] == nil {
                    self.effectPlayers[key] = player
                }
                // Only touch the audio session (and warm speech) when sound is
                // on, so a muted app never interrupts the user's own audio.
                if self.isEnabled {
                    self.activateSession()
                    self.prewarmSpeechIfNeeded()
                }
            }
        }
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

    /// Speaks a silent utterance so the very first real sum doesn't pay the
    /// one-off cost of spinning up the speech engine and loading the voice.
    private func prewarmSpeechIfNeeded() {
        guard !didPrewarmSpeech,
              LanguageManager.shared.effective.code == "en",
              let voice = englishVoice else { return }
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
    }

    private func deactivateSession() {
        guard sessionActive else { return }
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
        guard let effect = Self.effects.first(where: { $0.key == key }) else { return }
        // Preloaded by `prepare()`; the fallback only runs if a sound is needed
        // before preparation finished (rare — play happens well after launch).
        if effectPlayers[key] == nil {
            effectPlayers[key] = Self.makePlayer(named: effect.file, ext: effect.ext,
                                                 loops: 0, volume: effect.volume)
        }
        guard let player = effectPlayers[key] else { return }
        // Start past the file's leading silence so it sounds immediately.
        player.currentTime = effect.lead
        player.play()
    }

    // MARK: - Spoken sums (English only)

    /// Bumped on every request so a superseded (debounced) one can bow out.
    private var speechRequestToken = 0
    /// How long to wait after a new sum appears before speaking it. This keeps
    /// the synthesizer's start-up work out of the exact frames where the jump
    /// lands and SpriteKit rebuilds the answer board — the collision that made
    /// the game stutter — and debounces fast consecutive answers to the latest.
    private let speechStartDelay: TimeInterval = 0.3

    /// Requests that a sum such as "3 + 4 = ?" be read aloud in English
    /// ("three plus four"). No-op unless sound is on, a game is being played and
    /// the interface language is English — other languages get no spoken
    /// fallback. The actual speech is deferred (see `speechStartDelay`).
    func speakQuestion(_ prompt: String) {
        guard isEnabled, isGameplayActive else { return }
        guard LanguageManager.shared.effective.code == "en" else { return }
        guard englishVoice != nil else { return }
        let text = Self.spokenText(for: prompt)
        guard !text.isEmpty else { return }

        speechRequestToken += 1
        let token = speechRequestToken
        DispatchQueue.main.asyncAfter(deadline: .now() + speechStartDelay) { [weak self] in
            guard let self, token == self.speechRequestToken else { return } // superseded
            self.performSpeak(text)
        }
    }

    private func performSpeak(_ text: String) {
        guard isEnabled, isGameplayActive, let voice = englishVoice else { return }
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

    /// Turns a written sum into spoken English — just the sum itself, no "what
    /// is" wrapper. The numbers are left as numerals: the speech engine already
    /// says them correctly in English, at any size.
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
        let sides = prompt.components(separatedBy: "=")
        if sides.count == 2 {
            let lhs = spokenExpression(sides[0], unknownWord: "how many")
            let rhs = sides[1].trimmingCharacters(in: .whitespaces)
            if rhs == "?" {
                // The unknown is simply the answer: read the sum on its own.
                return lhs
            }
            // The unknown sits on the right (equivalent fractions "1/2 = ?/4"):
            // this one needs spelling out to make sense.
            return "\(lhs) is \(spokenExpression(rhs, unknownWord: "how many"))"
        }
        return spokenExpression(prompt, unknownWord: "what")
    }

    /// Speaks one side of a sum: numbers stay as numerals, symbols become words.
    private static func spokenExpression(_ expression: String, unknownWord: String) -> String {
        let tokens = expression.split(separator: " ").map(String.init)
        var words: [String] = []
        for (index, token) in tokens.enumerated() {
            switch token {
            case "+": words.append("plus")
            case "−", "-": words.append("minus")   // U+2212 is the game's minus
            case "÷": words.append("divided by")
            case "×":
                // A percentage or fraction "of" a whole reads more naturally
                // than "times"; between two plain numbers it stays "times".
                let previous = index > 0 ? tokens[index - 1] : ""
                words.append(previous.contains("%") ? "of" : "times")
            case "=": words.append("equals")
            case "?": words.append(unknownWord)
            default: words.append(spokenTerm(token, unknownWord: unknownWord))
            }
        }
        return words.joined(separator: " ")
    }

    /// A single number, percentage ("25%") or fraction ("3/4", "?/4").
    private static func spokenTerm(_ token: String, unknownWord: String) -> String {
        if token.hasSuffix("%") {
            return "\(numberWord(String(token.dropLast()), unknownWord)) percent"
        }
        if token.contains("/") {
            let parts = token.components(separatedBy: "/")
            if parts.count == 2 {
                return "\(numberWord(parts[0], unknownWord)) over \(numberWord(parts[1], unknownWord))"
            }
        }
        return numberWord(token, unknownWord)
    }

    private static func numberWord(_ text: String, _ unknownWord: String) -> String {
        text == "?" ? unknownWord : text
    }

    /// Picks the nicest English voice actually installed on the device.
    /// Prefers higher-quality (downloaded premium/enhanced) voices and a short
    /// list of clear, friendly voices, and skips the novelty/character voices.
    static func bestEnglishVoice() -> AVSpeechSynthesisVoice? {
        let novelty: Set<String> = ["Albert", "Bad News", "Bahh", "Bells", "Boing",
                                    "Bubbles", "Cellos", "Wobble", "Fred", "Good News",
                                    "Jester", "Organ", "Superstar", "Trinoids",
                                    "Whisper", "Zarvox", "Junior", "Ralph", "Kathy"]
        // Warmer, clear voices that suit a young audience, best first.
        let preferred = ["Ava", "Samantha", "Allison", "Susan", "Nicky",
                         "Serena", "Karen", "Catherine", "Moira", "Tessa"]

        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") && !novelty.contains($0.name) }
        guard !voices.isEmpty else {
            return AVSpeechSynthesisVoice(language: "en-US")
        }

        func score(_ v: AVSpeechSynthesisVoice) -> Int {
            var s = 0
            switch v.quality {
            case .premium:  s += 300
            case .enhanced: s += 200
            default:        s += 100
            }
            if let rank = preferred.firstIndex(of: v.name) {
                s += (preferred.count - rank) * 5
            }
            if v.language == "en-US" { s += 3 }        // most familiar accent
            else if v.language == "en-GB" { s += 2 }
            return s
        }

        return voices.max { score($0) < score($1) } ?? voices.first
    }

    // MARK: - Interruptions & backgrounding

    private func registerForInterruptions() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(handleInterruption(_:)),
                           name: AVAudioSession.interruptionNotification, object: nil)
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
        case .ended:
            if let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt,
               AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume) {
                startMusic()
            }
        @unknown default:
            break
        }
    }

    @objc private func appWillResignActive() {
        musicPlayer?.pause()
        synthesizer.stopSpeaking(at: .immediate)
    }

    @objc private func appDidBecomeActive() {
        // The loop plays app-wide, so resume it wherever the player is.
        startMusic()
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
