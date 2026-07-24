//
//  GameScene.swift
//  Jumping Fox
//
//  Doodle Jump–style gameplay with hard layout guarantees:
//  - blocks never overlap (AABB validation with a configurable margin);
//  - all normal blocks share ONE central size (rendering = collision);
//  - a block's value, position and size are immutable once visible —
//    new questions always get brand-new block instances (stable UUIDs);
//  - the correct answer is always reachable via a route that never
//    requires landing on an active wrong answer (graph/BFS validation);
//  - a layout only becomes active after all validations pass, in one
//    atomic update.
//

import SpriteKit
#if os(iOS)
import CoreMotion
import UIKit
#endif

// MARK: - Fixed colors (theme-independent)

enum GameColors {
    static let correctGreen = SKColor(red: 0.24, green: 0.68, blue: 0.32, alpha: 1)
    static let wrongRed = SKColor(red: 0.86, green: 0.27, blue: 0.23, alpha: 1)
    static let goldFlash = SKColor(red: 1.00, green: 0.78, blue: 0.15, alpha: 1)
    static let disabledFill = SKColor(white: 0.60, alpha: 1)
    static let disabledStroke = SKColor(white: 0.45, alpha: 1)
}

// MARK: - Powerups

/// Collectible pickups. Every pickup rides on an EMPTY (neutral) stone:
/// the icon floats above the platform and is collected by landing on it.
enum PowerupType: Equatable {
    case halfHeart   // +½ heart; only appears when ≥1 heart was lost
    case fullHeart   // +1 heart; only appears when ≥2 hearts were lost
    case eliminator  // shooting stars: streaks arc out and pop the wrong answers
    case tripler     // ×3: the next CORRECT answer scores triple
    case minusOne    // hazard: touching it costs 1 trophy (from a score of 10 up)
}

// MARK: - Platform block

/// Immutable identity/value/geometry, mutable status only.
final class GamePlatform: SKNode {
    enum Role {
        case neutralPlatform
        case answer
    }

    /// Visual status changes ONLY via a real, registered landing (or a
    /// question change for neutralResolved) — never via distance, height,
    /// approach, viewport position or spawning.
    enum Status {
        case active            // untouched answer block: keeps its active look
        case correctResolved   // landed correct: checkmark inside the block
        case wrongResolved     // landed wrong: cross inside the block
        case neutralResolved   // neutral platform, or superseded answer set
    }

    /// ONE central size for every normal block: rendering, collision,
    /// hitbox, placement validation and reachability all use this value.
    static let platformSize = CGSize(width: 72, height: 26)

    /// Each scene supplies one shared size. Keeping it on the node means
    /// rendering, pickups and collision can use the exact same geometry.
    let platformSize: CGSize

    let blockID = UUID()          // stable identity — never an array index
    let role: Role
    let value: String             // immutable after init
    /// The pickup riding on this (neutral) stone, if any.
    private(set) var powerup: PowerupType?
    private var powerupIcon: SKNode?

    /// Horizontal patrol (moving stones): points of travel to EACH side of
    /// the spawn centre. Every overlap/placement check must use the full
    /// swept range, never the momentary position.
    private(set) var patrolAmplitude: CGFloat = 0
    private(set) var patrolCenterX: CGFloat = 0

    /// Starts the side-to-side patrol. Only called after the scene has
    /// verified that the ENTIRE swept range is free of other blocks.
    func beginPatrol(amplitude: CGFloat, duration: TimeInterval) {
        patrolAmplitude = amplitude
        patrolCenterX = position.x
        let out = SKAction.moveBy(x: amplitude, y: 0, duration: duration)
        out.timingMode = .easeInEaseOut
        let across = SKAction.moveBy(x: -2 * amplitude, y: 0, duration: 2 * duration)
        across.timingMode = .easeInEaseOut
        let back = SKAction.moveBy(x: amplitude, y: 0, duration: duration)
        back.timingMode = .easeInEaseOut
        run(.repeatForever(.sequence([out, across, back])))
    }
    private let shape: SKShapeNode
    private let label: SKLabelNode
    /// When the value is a fraction (e.g. "3/4") this holds the stacked
    /// numerator-over-denominator artwork shown instead of the flat label,
    /// matching the way the question renders its fractions. `nil` otherwise.
    private let fractionNode: SKNode?
    private let statusIcon: SKLabelNode
    private let wrongMark: SKShapeNode
    private(set) var status: Status
    private(set) var hasBeenTriggered = false

    var isActiveAnswer: Bool { role == .answer && status == .active }

    init(role: Role, value: String = "", size: CGSize = GamePlatform.platformSize) {
        self.role = role
        self.value = value
        self.platformSize = size
        self.status = role == .answer ? .active : .neutralResolved
        let scale = size.width / Self.platformSize.width

        // Status icon sits in the centre of the block. It moves with the
        // block but never affects its collision or size.
        statusIcon = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        // The tick must fit comfortably inside the 26 pt high block.
        statusIcon.fontSize = 20 * scale
        statusIcon.verticalAlignmentMode = .center
        statusIcon.horizontalAlignmentMode = .center
        statusIcon.position = .zero
        statusIcon.zPosition = 2
        statusIcon.text = ""

        // A real diagonal cross, rather than a small glyph, makes a wrong
        // landing unmistakable while deliberately leaving the value visible.
        let wrongPath = CGMutablePath()
        wrongPath.move(to: CGPoint(x: -14 * scale, y: -6 * scale))
        wrongPath.addLine(to: CGPoint(x: 14 * scale, y: 6 * scale))
        wrongPath.move(to: CGPoint(x: -14 * scale, y: 6 * scale))
        wrongPath.addLine(to: CGPoint(x: 14 * scale, y: -6 * scale))
        wrongMark = SKShapeNode(path: wrongPath)
        wrongMark.strokeColor = GameColors.wrongRed
        wrongMark.lineWidth = 3 * scale
        wrongMark.lineCap = .round
        wrongMark.zPosition = 3
        wrongMark.isHidden = true

        shape = SKShapeNode(rectOf: size, cornerRadius: size.height / 2)
        shape.lineWidth = 2
        shape.zPosition = 0

        // A value like "3/4" is a fraction: render it stacked (numerator over a
        // bar over denominator) exactly like the question, instead of a flat
        // "3/4". Everything else keeps the single-line label.
        let fractionParts = Self.fractionParts(from: value)

        label = SKLabelNode(fontNamed: "AvenirNext-Bold")
        label.text = fractionParts == nil ? value : ""
        label.fontSize = (value.count >= 5 ? 13 : (value.count == 4 ? 15 : 18)) * scale
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        // Explicit z so the number always sits above the block fill even with
        // ignoresSiblingOrder batching enabled on the view.
        label.zPosition = 1

        if let parts = fractionParts {
            fractionNode = Self.makeFractionNode(numerator: parts.numerator,
                                                 denominator: parts.denominator,
                                                 scale: scale)
        } else {
            fractionNode = nil
        }

        super.init()
        addChild(shape)
        if role == .answer {
            if let fractionNode {
                addChild(fractionNode)
            } else {
                addChild(label)
            }
            addChild(statusIcon)
            addChild(wrongMark)
        }
    }

    /// Splits an answer value into a fraction's two parts when it is a plain
    /// `numerator/denominator` (both sides non-empty, no extra "/"), else `nil`.
    private static func fractionParts(from value: String) -> (numerator: String, denominator: String)? {
        let sides = value.split(separator: "/", omittingEmptySubsequences: false)
        guard sides.count == 2, !sides[0].isEmpty, !sides[1].isEmpty else { return nil }
        return (String(sides[0]), String(sides[1]))
    }

    /// Builds the stacked fraction shown on an answer stone. The stone is only
    /// 26 pt tall, so the digits are sized to stay clearly readable while
    /// leaving a small safety margin above and below the bar. Two-digit parts
    /// (e.g. "1/12") drop a step so they never touch the rounded ends.
    private static func makeFractionNode(numerator: String, denominator: String,
                                         scale: CGFloat) -> SKNode {
        let container = SKNode()
        container.zPosition = 1

        let maxDigits = max(numerator.count, denominator.count)
        // Comfortable on iPad and iPhone: single-digit parts get the roomy
        // size, two-plus-digit parts shrink just enough to fit the width.
        let fontSize = (maxDigits >= 2 ? 11.0 : 13.0) * scale
        // Vertical gap of each part's centre from the bar. Tied to the font so
        // the numerator/denominator clear the bar without crowding the edges.
        let offset = fontSize * 0.56

        func part(_ text: String, y: CGFloat) -> SKLabelNode {
            let node = SKLabelNode(fontNamed: "AvenirNext-Bold")
            node.text = text
            node.fontSize = fontSize
            node.fontColor = .white
            node.verticalAlignmentMode = .center
            node.horizontalAlignmentMode = .center
            node.position = CGPoint(x: 0, y: y)
            node.zPosition = 1
            return node
        }

        let num = part(numerator, y: offset)
        let den = part(denominator, y: -offset)
        container.addChild(num)
        container.addChild(den)

        // The bar spans the wider of the two parts plus a little overhang.
        let barWidth = max(num.frame.width, den.frame.width) + 6 * scale
        let bar = SKShapeNode(rectOf: CGSize(width: barWidth, height: max(1.5, 2 * scale)),
                              cornerRadius: scale)
        bar.fillColor = .white
        bar.strokeColor = .clear
        bar.position = .zero
        bar.zPosition = 1
        container.addChild(bar)

        return container
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Styling (never changes value, position or size)

    func styleAsNeutral(theme: AnimalCharacter) {
        shape.fillColor = theme.skNeutral
        shape.strokeColor = theme.skPrimary
    }

    func styleAsActiveAnswer(theme: AnimalCharacter, isCorrect: Bool, helperEnabled: Bool) {
        guard status == .active else { return }
        if helperEnabled {
            shape.fillColor = isCorrect ? GameColors.correctGreen : GameColors.wrongRed
            shape.strokeColor = shape.fillColor.withAlphaComponent(0.6)
        } else {
            shape.fillColor = theme.skPrimary
            shape.strokeColor = theme.skDeep
        }
        label.fontColor = .white
    }

    // MARK: Status transitions (only via a real landing / question change)

    /// Landed correct: replace the number with one clear, centred checkmark.
    func resolveCorrect(theme: AnimalCharacter) {
        guard status == .active else { return }
        status = .correctResolved
        hasBeenTriggered = true
        styleAsNeutral(theme: theme)
        label.isHidden = true
        fractionNode?.isHidden = true
        statusIcon.text = "✓"
        statusIcon.fontColor = GameColors.correctGreen
    }

    /// Landed wrong: register once, keep number/position/size, and draw a
    /// clear red cross straight through the number. No movement is involved.
    func resolveWrong() {
        guard status == .active else { return }
        status = .wrongResolved
        hasBeenTriggered = true
        shape.fillColor = GameColors.disabledFill
        shape.strokeColor = GameColors.disabledStroke
        label.fontColor = .white
        label.alpha = 0.85
        fractionNode?.alpha = 0.85
        wrongMark.isHidden = false
    }

    /// Superseded by a new question (never triggered by the player). The
    /// block stays exactly where it is — same value, position and size — so
    /// it can still be used as a stepping stone, but it is now visually
    /// deactivated: greyed out and dimmed with the shared disabled palette,
    /// so it clearly reads as an old option that no longer counts as an
    /// answer. This avoids the confusion of a live-looking tile that does
    /// nothing when landed on. No cross is drawn (it was never answered
    /// wrong), which keeps it distinct from a wrong-resolved block.
    func markSuperseded(theme: AnimalCharacter) {
        guard status == .active else { return }
        status = .neutralResolved
        statusIcon.text = ""
        wrongMark.isHidden = true
        shape.fillColor = GameColors.disabledFill
        shape.strokeColor = GameColors.disabledStroke
        label.fontColor = .white
        label.alpha = 0.75
        fractionNode?.alpha = 0.75
        alpha = 0.9
    }

    // MARK: Powerups (neutral stones only)

    /// Puts a gently bobbing pickup icon on this empty stone. The icon is
    /// pure decoration: collision, size and placement stay untouched.
    /// `fillsRightHalf` matches the HUD: which half of the current heart
    /// is open (hearts fill left half first).
    func attachPowerup(_ type: PowerupType, theme: AnimalCharacter,
                       fillsRightHalf: Bool = false) {
        guard role == .neutralPlatform, powerup == nil else { return }
        powerup = type
        let scale = platformSize.width / Self.platformSize.width
        let icon = Self.makePowerupIcon(type, theme: theme, fillsRightHalf: fillsRightHalf)
        icon.position = CGPoint(x: 0, y: platformSize.height / 2 + 18)
        icon.zPosition = 4
        // Sparkle in (also covers attaching to an on-screen stone), then bob.
        icon.setScale(0.01)
        icon.run(.sequence([
            .scale(to: 1.2 * scale, duration: 0.18),
            .scale(to: scale, duration: 0.12),
            .repeatForever(.sequence([
                .moveBy(x: 0, y: 5, duration: 0.6),
                .moveBy(x: 0, y: -5, duration: 0.6)
            ]))
        ]))
        addChild(icon)
        powerupIcon = icon
    }

    /// Retired by the firework: instantly no longer an answer (landing on
    /// it is a plain bounce); the visual pop happens when the spark hits.
    func retireForElimination() {
        guard status == .active else { return }
        status = .neutralResolved
    }

    /// Disables a block without altering its current artwork. This is used
    /// when the answer is revealed: the player should still see the answer
    /// group exactly as it was, rather than seeing wrong options turn grey.
    func deactivateKeepingAppearance() {
        guard status == .active else { return }
        status = .neutralResolved
    }

    /// Consumes the pickup (once) with a small pop animation.
    /// Returns the pickup's actual local centre before removing it. The
    /// follow-up flight can therefore begin at the icon itself, including its
    /// current bob offset, instead of at an approximate platform coordinate.
    func takePowerup() -> (type: PowerupType, localOrigin: CGPoint)? {
        guard let type = powerup else { return nil }
        powerup = nil
        let localOrigin = powerupIcon?.position
            ?? CGPoint(x: 0, y: platformSize.height / 2 + 18)
        if let icon = powerupIcon {
            powerupIcon = nil
            icon.removeAllActions()
            icon.run(.sequence([
                .group([.scale(to: 1.7, duration: 0.22), .fadeOut(withDuration: 0.22)]),
                .removeFromParent()
            ]))
        }
        return (type, localOrigin)
    }

    /// Used when the tutorial's −1 lesson has been completed: every other
    /// visible hazard must disappear without applying another penalty.
    func removePowerup() {
        powerup = nil
        powerupIcon?.removeAllActions()
        powerupIcon?.removeFromParent()
        powerupIcon = nil
    }

    static func makePowerupIcon(_ type: PowerupType, theme: AnimalCharacter,
                                fillsRightHalf: Bool) -> SKNode {
        switch type {
        case .halfHeart:
            return makeHeartIcon(theme: theme, half: true, fillsRightHalf: fillsRightHalf)
        case .fullHeart:
            return makeHeartIcon(theme: theme, half: false, fillsRightHalf: false)
        case .eliminator:
            return makeStarIcon(theme: theme, radius: 12)
        case .tripler:
            return makeBubbleIcon(text: "×3", fill: theme.skPrimary)
        case .minusOne:
            return makeBubbleIcon(text: "−1", fill: GameColors.wrongRed)
        }
    }

    private static func makeBubbleIcon(text: String, fill: SKColor) -> SKNode {
        let circle = SKShapeNode(circleOfRadius: 14)
        circle.fillColor = fill
        circle.strokeColor = .white
        circle.lineWidth = 2
        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.text = text
        label.fontSize = 14
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.zPosition = 1
        circle.addChild(label)
        return circle
    }

    // MARK: Heart drawing (mirrors the HUD hearts exactly)

    /// The same visual language as the top-right HUD hearts: a dimmed full
    /// heart in the theme's deep colour with (for a half heart) only ONE
    /// half filled — the half that is currently open in the HUD.
    static func makeHeartIcon(theme: AnimalCharacter, half: Bool,
                              fillsRightHalf: Bool) -> SKNode {
        let container = SKNode()
        let radius: CGFloat = 11
        let base = SKShapeNode(path: heartPath(radius: radius))
        base.fillColor = theme.skDeep.withAlphaComponent(half ? 0.28 : 1)
        base.strokeColor = .clear
        container.addChild(base)
        if half {
            let crop = SKCropNode()
            let mask = SKSpriteNode(color: .white,
                                    size: CGSize(width: radius * 1.1, height: radius * 2.4))
            mask.position = CGPoint(x: fillsRightHalf ? radius * 0.55 : -radius * 0.55, y: 0)
            crop.maskNode = mask
            let fill = SKShapeNode(path: heartPath(radius: radius))
            fill.fillColor = theme.skDeep
            fill.strokeColor = .clear
            crop.addChild(fill)
            crop.zPosition = 1
            container.addChild(crop)
        }
        return container
    }

    /// Five-point star, flat fill in the theme colour — the same drawn
    /// visual family as the hearts (no emoji).
    static func makeStarIcon(theme: AnimalCharacter, radius: CGFloat) -> SKShapeNode {
        let star = SKShapeNode(path: starPath(radius: radius))
        star.fillColor = theme.skDeep
        star.strokeColor = .clear
        return star
    }

    static func starPath(radius r: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let inner = r * 0.42
        for i in 0..<10 {
            let angle = CGFloat(i) * .pi / 5 + .pi / 2 // start at the top point
            let radius = i.isMultiple(of: 2) ? r : inner
            let point = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        p.closeSubpath()
        return p
    }

    /// Classic two-lobe heart, centred on the origin, tip at the bottom.
    private static func heartPath(radius r: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: -r))
        p.addCurve(to: CGPoint(x: -r, y: r * 0.35),
                   control1: CGPoint(x: -r * 0.6, y: -r * 0.5),
                   control2: CGPoint(x: -r, y: -r * 0.1))
        p.addArc(center: CGPoint(x: -r * 0.5, y: r * 0.35), radius: r * 0.5,
                 startAngle: .pi, endAngle: 0, clockwise: true)
        p.addArc(center: CGPoint(x: r * 0.5, y: r * 0.35), radius: r * 0.5,
                 startAngle: .pi, endAngle: 0, clockwise: true)
        p.addCurve(to: CGPoint(x: 0, y: -r),
                   control1: CGPoint(x: r, y: -r * 0.1),
                   control2: CGPoint(x: r * 0.6, y: -r * 0.5))
        p.closeSubpath()
        return p
    }
}

// MARK: - Game scene

final class GameScene: SKScene {
    private let state: GameState
    private var theme = CharacterCatalog.character(id: "fox")

    /// Fixed wallpaper behind the whole scene: a subtle, tiled repeat of the
    /// level's own icon (plus, minus, …) in the theme colour. Sits behind the
    /// jump tiles and never scrolls.
    private var backgroundPattern: SKSpriteNode?

    // Player
    private var player = SKNode()
    /// The visible player. The fox uses the supplied mascot artwork; the
    /// Premium animals keep their emoji appearance.
    private var playerSprite = SKNode()
    private var springNode = SKShapeNode()
    private var velocityY: CGFloat = 0
    private var velocityX: CGFloat = 0
    private var targetX: CGFloat?
    private var squashTimer: CGFloat = 0
    private var currentScaleX: CGFloat = 1
    private var currentScaleY: CGFloat = 1
    private var facing: CGFloat = 1

    // Physics tuning
    private let gravity: CGFloat = -1900
    /// iPad gets one larger, internally consistent playfield. Horizontal
    /// steering deliberately keeps its original tuning.
    private var tileScale: CGFloat = 1
    private var tileSize: CGSize = GamePlatform.platformSize
    private var verticalGameplayScale: CGFloat { tileSize.width / GamePlatform.platformSize.width }
    private var bounceVelocity: CGFloat { 980 * sqrt(verticalGameplayScale) }
    private var playerHalfHeight: CGFloat { 20 * verticalGameplayScale }
    private var playerHalfWidth: CGFloat { 26 * verticalGameplayScale }
    private let maxHorizontalSpeed: CGFloat = 650

    // Tilt controls
#if os(iOS)
    private let motionManager = CMMotionManager()
#endif
    private let tiltDeadZone: CGFloat = 0.03
    private let tiltSensitivity: CGFloat = 1500
    private var lastReportedTilt: CGFloat = 0

    // Platforms & layout rules.
    // Reachability: max jump height = v²/2g ≈ 253 pt; with the 80% safety
    // factor (~202 pt) every band gap incl. jitter (≤ 135 + 24 = 159 pt)
    // stays climbable. Placement margin keeps visible air between blocks
    // (based on real block size + landing space; configurable).
    private var platforms: [GamePlatform] = []
    /// The first stone in each spawned band stays within a safe horizontal
    /// step of this anchor. This guarantees a neutral route on wide iPads
    /// instead of relying on random placement across the whole display.
    private var routeAnchorX: CGFloat = 0
    private var nextSpawnY: CGFloat = 0
    private let minBandGap: CGFloat = 95
    private let maxBandGap: CGFloat = 135
    private let bandJitter: CGFloat = 12
    private let jumpSafetyFactor: CGFloat = 0.8
    private let placementMargin: CGFloat = 22   // visible air around every block
    /// Keeps enlarged iPad tiles entirely inside the side edges.
    private var tileEdgeInset: CGFloat { max(48, tileSize.width / 2 + placementMargin) }
    /// Minimum centre-to-centre distance between any two ANSWER blocks.
    /// Answer blocks need far more air than neutral platforms: a jump
    /// aimed at one answer must never accidentally clip a neighbour.
    private let minAnswerSeparation: CGFloat = 128
    private let correctApproachWidth: CGFloat = 116
    private let correctApproachBelow: CGFloat = 220
    /// Also keep the zone ABOVE the correct block clear: after a fast
    /// launch the player often overshoots the correct block and falls
    /// back down — nothing wrong may be waiting in that column.
    private let correctApproachAbove: CGFloat = 130

    // Spawn zone: new blocks are only ever created ABOVE the visible
    // viewport. The margin covers full block height (26), the highest
    // vertical speed (springboard launch, 1250 pt/s) over a few frames
    // of render latency, plus animation headroom.
    private let spawnMargin: CGFloat = 80
    // Forward buffer: bands are prepared several rows ahead so fast
    // climbs never catch up with the generator. Large enough to also
    // cover the raised window used by skip sets (correct block one band
    // higher than the wrong answers).
    private let spawnAheadBuffer: CGFloat = 900

    private var maxJumpHeight: CGFloat { bounceVelocity * bounceVelocity / (2 * -gravity) }
    private var helperEnabled = false
    private var totalClimb: CGFloat = 0

    /// While true the field stays fully set up and rendered, but no gameplay
    /// physics advance. Used to hold the field still behind the pre-game
    /// intro card, then released the moment the card is dismissed.
    var isFrozen = false

    /// 2 wrong blocks at the start (3 answer blocks total), more as the
    /// player climbs — never more than the question can supply.
    private var wrongAnswerCount: Int {
        min(2 + Int(totalClimb / 2500), 4)
    }

    // Deferred answer refresh — the next set only activates after the
    // confirmation, never in the landing frame.
    private var answerRefreshAt: TimeInterval?
    /// The question the visible answer group was built for. Used to recognise a
    /// genuinely duplicate build of the SAME question, without mistaking a
    /// leftover block that happens to carry the next question's answer for one.
    private var answerSetPrompt: String?
    private var lastReachabilityCheck: TimeInterval = 0

    // Skip sets: occasionally the first band deliberately contains ONLY
    // wrong answers and the correct block waits one band higher, so the
    // player must recognise nothing fits and jump on past. Rare (about
    // 1 in 10), never twice in a row, never in the first two questions.
    private let skipSetChance = 0.10
    private var setsBuilt = 0
    private var lastSetWasSkip = false
    /// Vertical offset of the raised correct-block window; larger than
    /// the normal window height so the two bands never blend together.
    private let skipSetRaise: CGFloat = 420

    // Powerups & variation.
    /// Hearts: independent rolls per correct answer, so they feel genuinely
    /// random, and only when they can actually heal.
    private let heartChance = 0.15
    /// A run's length now depends on its practice mode (Order 20, Random 30,
    /// Mixed 40, Supermix 50), so the per-run pickup caps are derived from that
    /// goal instead of being fixed. This keeps the *density* of specials the
    /// same everywhere: roughly one per 15 trophies, so a short Order run no
    /// longer receives a full 30-trophy run's worth of pickups.
    private var runTrophyGoal: Int { ProgressStore.maximumTrophies(for: state.level) }
    private func perRunCap(forWindow window: Int) -> Int { max(1, window / 15) }

    /// Shooting star: disarms the current set.
    private let eliminatorChance = 0.3
    private var maxEliminatorsPerRun: Int { perRunCap(forWindow: runTrophyGoal) }
    private var eliminatorsSpawned = 0
    /// The star only makes sense under a real GROUP, so those sets are
    /// raised a little to reserve a visible strip below the group.
    private let eliminatorRaise: CGFloat = 140
    /// ×3 tripler: never near the run's trophy goal.
    private let triplerChance = 0.12
    private var maxTriplersPerRun: Int { perRunCap(forWindow: runTrophyGoal) }
    private var triplersSpawned = 0
    private var triplerAura: SKNode?
    /// −1 hazard: same odds as the ×3, but only once the player has real
    /// trophies to spare. It never appears below 20, so a 20-trophy Order run
    /// stays hazard-free and only the longer modes can meet it — and its cap
    /// counts only the trophies available ABOVE that threshold.
    private let minusOneChance = 0.12
    private let minusOneScoreThreshold = 20
    private var maxMinusOnesPerRun: Int {
        perRunCap(forWindow: runTrophyGoal - minusOneScoreThreshold)
    }
    private var minusOnesSpawned = 0
    /// Spread: at least this many correct answers between ANY two specials,
    /// so they never cluster while each individual roll stays random.
    private let specialCooldown = 2
    private var answersSinceSpecial = 99
    /// Decoy: sometimes one extra wrong block floats far above the group,
    /// so a block standing alone is NOT automatically the correct answer.
    private let decoyChance = 0.20
    /// One guided second chance after a mistake: the next correct block is
    /// helper-green until the player actually lands on it.
    private var redemptionArmed = false

    // Tutorial-only flow.  It deliberately lives in the scene rather than in
    // a modal view, so jumping, steering and scrolling never stop.
    private let tutorial = TutorialProgress.shared
    private var tutorialStartX: CGFloat = 0
    private var tutorialMovedLeft = false
    private var tutorialMovedRight = false
    private var tutorialMovementConfirmedAt: TimeInterval?
    private var tutorialHeartCount = 0
    private var tutorialNextPickupAt: TimeInterval = 0
    private var tutorialAwaitingQuestionTap = false
    private var preserveAnswerAppearanceAfterTutorialReveal = false
    /// After the tutorial star clears the wrong answers, the remaining good
    /// answer is intentionally the only answer until it is collected.
    private var awaitingCorrectAfterTutorialStar = false

    /// Stages that must not silently be repopulated by the normal answer
    /// watchdog. Without this guard the watchdog could create an answer set
    /// during the movement/stone-only lessons.
    private var tutorialSuppressesAnswerTiles: Bool {
        guard tutorial.isActive else { return false }
        if tutorial.currentStep == 8 { return !tutorial.triplerAnswerPending }
        return [1, 2, 7, 9, 10].contains(tutorial.currentStep)
    }

    // Permanent bottom springboard: separate platform type, own height,
    // independent of the answer generator.
    private var springboard = SKShapeNode()
    /// Keep the safety bounce line visible immediately above the equation
    /// HUD. Every start, reachability and collision calculation uses this
    /// single anchor.
    private let springboardY: CGFloat = 142
    private var springboardVelocity: CGFloat { 1250 * sqrt(verticalGameplayScale) }

    // Loop
    private var lastUpdateTime: TimeInterval = 0
    private var started = false

    // Haptics: one retained generator kept "warm" via prepare(), so the
    // Taptic Engine never cold-starts on the first correct landing (the
    // cold start is what caused the noticeable hitch on the first jump).
#if os(iOS)
    private let feedbackGenerator = UINotificationFeedbackGenerator()
    private let heartFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    /// The soft tap played when the answer-hint ("?") is used. Retained and
    /// kept warm just like the others so the tutorial's "tap the question mark"
    /// step doesn't cold-start the Taptic Engine and hitch on first use.
    private let hintFeedbackGenerator = UIImpactFeedbackGenerator(style: .soft)
#endif

    init(state: GameState) {
        self.state = state
        super.init(size: .zero)
        scaleMode = .resizeFill
        // Set this before SpriteView attaches and lays out the scene. Without
        // it its first frame may use the default neutral-grey clear colour.
        backgroundColor = CharacterCatalog.current(
            isPremium: GameSettings.premiumUnlockedCache
        ).skSky
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        startIfNeeded()
        startMotionUpdates()
#if os(iOS)
        // Warm the Taptic Engine before the first correct landing so the
        // first success haptic doesn't cause a frame hitch.
        feedbackGenerator.prepare()
        // Same warm-up for the heart-pickup and answer-hint taps, so neither
        // cold-starts the Taptic Engine on first use. The hint tap is also
        // re-primed right before tutorial step 6 (see prepareHintHaptic), since
        // a prepare() here has worn off by the time that step is reached.
        heartFeedbackGenerator.prepare()
        hintFeedbackGenerator.prepare()
#endif
        prewarmCheckmarkGlyph()
    }

    /// The FIRST render of each effect type compiles SpriteKit's shape
    /// shaders, builds crop-node masks and rasterises label glyphs — a
    /// one-off cost that used to hitch the game the first time a powerup,
    /// flight or pop appeared. Render one invisible instance of everything
    /// at start-up so every later first use is warm.
    private func prewarmEffects() {
        // IMPORTANT: the view renders with shouldCullNonVisibleNodes, so
        // the stash must sit INSIDE the viewport — off-screen nodes would
        // be culled and nothing would compile. Practically invisible via
        // near-zero alpha, tucked behind everything.
        let stash = SKNode()
        stash.alpha = 0.001
        stash.position = CGPoint(x: size.width / 2, y: size.height / 2)
        stash.zPosition = -100
        addChild(stash)

        // Hearts (full + cropped half), star icon, ×3 bubble & badge text, and
        // the −1 hazard bubble so its glyph is rasterised ahead of first use.
        stash.addChild(GamePlatform.makeHeartIcon(theme: theme, half: false, fillsRightHalf: false))
        stash.addChild(GamePlatform.makeHeartIcon(theme: theme, half: true, fillsRightHalf: true))
        stash.addChild(GamePlatform.makeStarIcon(theme: theme, radius: 12))
        stash.addChild(makeTriplerBubble(radius: 16))
        stash.addChild(makeBubbleIcon(text: "−1", fill: GameColors.wrongRed))
        stash.addChild(GamePlatform.makePowerupIcon(.tripler, theme: theme, fillsRightHalf: false))
        stash.addChild(GamePlatform.makePowerupIcon(.minusOne, theme: theme, fillsRightHalf: false))

        // Stroked shapes used by the animations: ping ring, arc streak,
        // burst dot, aura glow.
        let ring = SKShapeNode(circleOfRadius: 10)
        ring.strokeColor = theme.skPrimary
        ring.lineWidth = 3
        ring.fillColor = .clear
        stash.addChild(ring)

        let arc = CGMutablePath()
        arc.move(to: .zero)
        arc.addQuadCurve(to: CGPoint(x: 40, y: 40), control: CGPoint(x: 8, y: 32))
        let line = SKShapeNode(path: arc)
        line.strokeColor = theme.skPrimary
        line.lineWidth = 3
        line.lineCap = .round
        stash.addChild(line)

        let dot = SKShapeNode(circleOfRadius: 3)
        dot.fillColor = theme.skPrimary
        stash.addChild(dot)

        let glow = SKShapeNode(circleOfRadius: 46)
        glow.fillColor = theme.skPrimary.withAlphaComponent(0.2)
        glow.strokeColor = theme.skPrimary.withAlphaComponent(0.55)
        glow.lineWidth = 2
        stash.addChild(glow)

        // The wrong-answer cross stays hidden on every answer block until the
        // first wrong landing, so its stroked path is never rendered during
        // normal play. Warm a matching one (same style as GamePlatform's
        // wrongMark) so that first cross doesn't hitch.
        let crossPath = CGMutablePath()
        crossPath.move(to: CGPoint(x: -14, y: -6))
        crossPath.addLine(to: CGPoint(x: 14, y: 6))
        crossPath.move(to: CGPoint(x: -14, y: 6))
        crossPath.addLine(to: CGPoint(x: 14, y: -6))
        let cross = SKShapeNode(path: crossPath)
        cross.strokeColor = GameColors.wrongRed
        cross.lineWidth = 3
        cross.lineCap = .round
        stash.addChild(cross)

        // One frame is enough to build everything; then clean up.
        stash.run(.sequence([.wait(forDuration: 0.5), .removeFromParent()]))
    }

    /// The first time an SKLabelNode renders the "✓" glyph, SpriteKit builds
    /// its font texture — a one-off cost that used to land on the first
    /// correct answer. Render it once off-screen at start-up to absorb that.
    private func prewarmCheckmarkGlyph() {
        let warmUp = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        warmUp.text = "✓"
        warmUp.fontSize = 20
        warmUp.alpha = 0
        warmUp.position = CGPoint(x: -1000, y: -1000)
        addChild(warmUp)
        warmUp.run(.sequence([.wait(forDuration: 0.1), .removeFromParent()]))
    }

    override func willMove(from view: SKView) {
        stopMotionUpdates()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard started else {
            startIfNeeded()
            return
        }
        guard oldSize.width > 0, oldSize.height > 0,
              size.width > 50, size.height > 50 else { return }

        // SpriteView uses the available device size.  When a split view,
        // rotation or iPad window changes that size, retain the current run
        // but move horizontal scene anchors into their equivalent new position.
        // Without this the springboard and wallpaper stayed at the old width.
        let horizontalScale = size.width / oldSize.width
        player.position.x *= horizontalScale
        for platform in platforms {
            platform.position.x *= horizontalScale
        }
        setupSpringboard()
        updateBackgroundPattern()
    }

    private func startIfNeeded() {
        guard !started, size.width > 50, size.height > 50 else { return }
        started = true
        // The phone layout remains pixel-for-pixel unchanged.  Portrait iPads
        // receive larger tiles, mascot and vertical jump arc without changing
        // the original horizontal input response.
        tileScale = min(1.35, max(1, size.width / 560))
        tileSize = CGSize(width: GamePlatform.platformSize.width * tileScale,
                          height: GamePlatform.platformSize.height * tileScale)
        setupSpringboard()
        setupPlayer()
        layoutNewGame()
        prewarmEffects()
    }

    // MARK: Motion

    private func startMotionUpdates() {
#if os(iOS)
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates()
#endif
    }

    private func stopMotionUpdates() {
#if os(iOS)
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
#endif
    }

    /// Current tilt (-1...1), nil when unavailable (simulator, Mac).
    private var currentTilt: CGFloat? {
#if os(iOS)
        guard let gravityVector = motionManager.deviceMotion?.gravity else { return nil }
        return CGFloat(gravityVector.x)
#else
        return nil
#endif
    }

    // MARK: Setup

    /// One continuous collider across the full width — no gaps at the
    /// edges, wrap-proof (the catch check ignores x entirely).
    private func setupSpringboard() {
        springboard.removeFromParent()
        springboard = SKShapeNode(rectOf: CGSize(width: size.width + 8, height: 14), cornerRadius: 7)
        springboard.position = CGPoint(x: size.width / 2, y: springboardY)
        springboard.zPosition = 5
        addChild(springboard)
    }

    private func setupPlayer() {
        player.removeFromParent()
        player = SKNode()
        configurePlayerSprite()

        springNode = makeSpring()
        springNode.position = CGPoint(x: 0, y: -18 * verticalGameplayScale)
        player.addChild(springNode)

        player.zPosition = 10
        addChild(player)
    }

    /// Changes the artwork without changing the player's collision box or
    /// movement node. This keeps the original jump and squash animation
    /// identical for every character.
    private func configurePlayerSprite() {
        playerSprite.removeFromParent()

        // Every character has its own artwork (with a built-in coil spring),
        // rendered at the same size so the jump and squash animation is
        // identical for all of them.
        let sprite = SKSpriteNode(texture: theme.skTexture)
        sprite.size = CGSize(width: 82 * verticalGameplayScale,
                             height: 82 * verticalGameplayScale)
        playerSprite = sprite

        player.addChild(playerSprite)
    }

    /// Drawn coil spring under the character.
    private func makeSpring() -> SKShapeNode {
        let path = CGMutablePath()
        let coilWidth: CGFloat = 16 * verticalGameplayScale
        let coilHeight: CGFloat = 16 * verticalGameplayScale
        let segments = 5
        path.move(to: .zero)
        for i in 1...segments {
            let x: CGFloat = (i == segments) ? 0 : (i.isMultiple(of: 2) ? -coilWidth / 2 : coilWidth / 2)
            let y = -coilHeight * CGFloat(i) / CGFloat(segments)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        let node = SKShapeNode(path: path)
        node.lineWidth = 2.5 * verticalGameplayScale
        node.lineCap = .round
        node.lineJoin = .round
        return node
    }

    /// Places the player and an initial sparse set of platforms.
    func layoutNewGame() {
        guard started else { return }
        // Gameplay must start immediately.  The tutorial is an in-game
        // overlay, never a reason to freeze the physics loop.
        isFrozen = false
        for platform in platforms { platform.removeFromParent() }
        platforms.removeAll()

        helperEnabled = GameSettings.answerHelperEnabled
        tutorial.beginIfNeeded(helperEnabled: helperEnabled)
        theme = CharacterCatalog.current(isPremium: GameSettings.premiumUnlockedCache)
        backgroundColor = theme.skSky
        updateBackgroundPattern()
        configurePlayerSprite()
        springNode.strokeColor = theme.skDeep
        // Every character's artwork already includes its own coil spring,
        // so the separate drawn coil stays hidden to avoid a doubled spring.
        springNode.isHidden = true
        springboard.fillColor = theme.skPrimary
        springboard.strokeColor = theme.skDeep
        springboard.lineWidth = 2

        player.position = CGPoint(x: size.width / 2,
                                  y: springboardY + 110 * verticalGameplayScale)
        routeAnchorX = player.position.x
        player.zRotation = 0
        velocityY = bounceVelocity
        velocityX = 0
        targetX = nil
        squashTimer = 0
        totalClimb = 0
        lastUpdateTime = 0
        answerRefreshAt = nil
        answerSetPrompt = nil
        lastReachabilityCheck = 0
        setsBuilt = 0
        lastSetWasSkip = false
        eliminatorsSpawned = 0
        triplersSpawned = 0
        minusOnesSpawned = 0
        answersSinceSpecial = 99
        redemptionArmed = false
        tutorialStartX = player.position.x
        tutorialMovedLeft = false
        tutorialMovedRight = false
        tutorialMovementConfirmedAt = nil
        tutorialHeartCount = 0
        tutorialNextPickupAt = 0
        tutorialAwaitingQuestionTap = false
        preserveAnswerAppearanceAfterTutorialReveal = false
        awaitingCorrectAfterTutorialStar = false
        setTriplerVisual(false)

        nextSpawnY = springboardY + 194 * verticalGameplayScale
        // The movement lesson uses only the full-width springboard.  No
        // stones or answer tiles are created until left AND right movement
        // has been demonstrated.
        if !(tutorial.isActive && tutorial.currentStep == 1) {
            addNeutralPlatform(at: CGPoint(x: size.width / 2,
                                            y: springboardY + 64 * verticalGameplayScale),
                               allowMoving: false)
            spawnPlatformsIfNeeded()
            buildAnswerSet() // validated before the first playable frame
        }
    }

    /// Restart after game over.
    func resetGame() {
        state.reset()
        layoutNewGame()
    }

    // MARK: Themed background pattern

    /// The number + operation sign that fills the wallpaper for a level, built
    /// from the level's own card number so it reads like the level itself:
    /// "2+", "−2", "2×", "2%", "2★" (Supermix). The sign trails the number,
    /// except subtraction where it naturally leads. Fractions draw a stacked
    /// fraction, so they return nil here.
    private func backgroundPatternText() -> String? {
        let n = state.level.cardNumber
        switch state.level.category {
        case .addition, .additionMix: return "\(n)+"
        case .subtraction, .subtractionMix: return "−\(n)"
        case .tables, .tablesMix: return "\(n)×"
        case .percentages, .percentagesMix: return "\(n)%"
        case .superBasic, .superTimes, .superFraction, .superAll: return "\(n)★"
        case .fractions, .fractionsMix: return nil
        }
    }

    /// Rebuilds the fixed wallpaper: a staggered grid of the level's icon in a
    /// faint tint of the theme colour, sized to the viewport and pinned behind
    /// everything. Regenerated whenever the field is (re)laid out.
    private func updateBackgroundPattern() {
        backgroundPattern?.removeFromParent()
        backgroundPattern = nil
        guard size.width > 0, size.height > 0 else { return }
#if os(iOS)
        guard let glyph = patternGlyphImage(),
              let texture = makePatternTexture(glyph: glyph) else { return }
        let node = SKSpriteNode(texture: texture)
        node.size = CGSize(width: size.width, height: size.height)
        node.position = CGPoint(x: size.width / 2, y: size.height / 2)
        node.zPosition = -50            // behind springboard (5) and platforms
        addChild(node)
        backgroundPattern = node
#endif
    }

#if os(iOS)
    /// One tinted tile glyph for the wallpaper: a number + sign for the
    /// arithmetic levels (Supermix included) or a stacked fraction for the
    /// fraction levels.
    private func patternGlyphImage() -> UIImage? {
        // A faint wash of the theme colour keeps the pattern subtle over the sky.
        let tint = theme.skPrimary.withAlphaComponent(0.10)
        // The wallpaper belongs to the playfield, not to the device pixels.
        // Use the same metric as stones and mascot so iPad's larger field
        // does not leave a visually tiny, dense backdrop behind them.
        let scale = verticalGameplayScale
        switch state.level.category {
        case .fractions:
            // The plain fraction levels have ONE denominator (their card number),
            // so the wallpaper mirrors it: 1/3 on the thirds level, etc.
            let denominator = Int(state.level.cardNumber) ?? 2
            return makeFractionGlyph(numerator: 1, denominator: max(2, denominator), color: tint, scale: scale)
        case .fractionsMix:
            // The mixed levels span many denominators, so they fall back to halves.
            return makeFractionGlyph(numerator: 1, denominator: 2, color: tint, scale: scale)
        default:
            return makeTextGlyph(backgroundPatternText() ?? "", color: tint, scale: scale)
        }
    }

    /// A single-line "number + sign" tile (e.g. "2+"), drawn in the rounded
    /// heavy face used across the game and tinted for the wallpaper.
    private func makeTextGlyph(_ text: String, color: UIColor, scale: CGFloat) -> UIImage {
        let base = UIFont.systemFont(ofSize: 16 * scale, weight: .heavy)
        let font = base.fontDescriptor.withDesign(.rounded)
            .map { UIFont(descriptor: $0, size: 16 * scale) } ?? base
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let str = NSAttributedString(string: text, attributes: attrs)
        let textSize = str.size()
        let glyphSize = CGSize(width: ceil(textSize.width) + 6 * scale,
                               height: ceil(textSize.height) + 2 * scale)
        let renderer = UIGraphicsImageRenderer(size: glyphSize)
        return renderer.image { _ in
            str.draw(at: CGPoint(x: (glyphSize.width - textSize.width) / 2,
                                 y: (glyphSize.height - textSize.height) / 2))
        }
    }

    /// A small stacked fraction — numerator over a bar over denominator —
    /// matching the in-game fraction style rather than a symbol. The tile width
    /// grows with the digits so two-digit denominators (e.g. 1/12) still fit.
    private func makeFractionGlyph(numerator: Int, denominator: Int, color: UIColor,
                                   scale: CGFloat) -> UIImage {
        let font = UIFont.systemFont(ofSize: 11 * scale, weight: .heavy)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let num = NSAttributedString(string: "\(numerator)", attributes: attrs)
        let den = NSAttributedString(string: "\(denominator)", attributes: attrs)
        let nSize = num.size()
        let dSize = den.size()
        let glyphSize = CGSize(width: max(nSize.width, dSize.width) + 8 * scale,
                               height: 26 * scale)
        let renderer = UIGraphicsImageRenderer(size: glyphSize)
        return renderer.image { ctx in
            num.draw(at: CGPoint(x: (glyphSize.width - nSize.width) / 2, y: 0))
            den.draw(at: CGPoint(x: (glyphSize.width - dSize.width) / 2,
                                 y: glyphSize.height - dSize.height))
            // The fraction bar, centred vertically.
            color.setFill()
            ctx.cgContext.fill(CGRect(x: 2 * scale, y: glyphSize.height / 2 - scale,
                                      width: glyphSize.width - 4 * scale, height: 2 * scale))
        }
    }

    /// Tiles a single glyph across the viewport into one image and wraps it as
    /// an SKTexture, so the wallpaper costs a single sprite/draw call. Spacing
    /// grows with the glyph so wide tiles (e.g. "1000+") don't crowd together.
    private func makePatternTexture(glyph: UIImage) -> SKTexture? {
        let scale = verticalGameplayScale
        let step = max(58 * scale, glyph.size.width + 22 * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            var row = 0
            var y: CGFloat = step / 2
            while y < size.height + step {
                // Offset every other row for a geometric, non-gridlocked repeat.
                let rowShift: CGFloat = row.isMultiple(of: 2) ? 0 : step / 2
                var x: CGFloat = step / 2
                while x < size.width + step {
                    let origin = CGPoint(x: x + rowShift - glyph.size.width / 2,
                                         y: y - glyph.size.height / 2)
                    glyph.draw(at: origin)
                    x += step
                }
                y += step
                row += 1
            }
        }
        return SKTexture(image: image)
    }
#endif

    // MARK: Geometry & placement validation

    private func wrapDx(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        let d = abs(a - b)
        return min(d, size.width - d)
    }

    private func blockRect(at center: CGPoint) -> CGRect {
        CGRect(x: center.x - tileSize.width / 2,
               y: center.y - tileSize.height / 2,
               width: tileSize.width,
               height: tileSize.height)
    }

    /// The full horizontal footprint a platform can occupy. A patrolling
    /// stone drifts up to `patrolAmplitude` to EACH side of its spawn
    /// centre, so its rect is widened to that entire swept range; a static
    /// stone returns its fixed rect. Every overlap/placement check must use
    /// THIS, never the momentary position, or a drifting stone can slide
    /// into a neighbour that was validated only at its spawn point.
    private func sweptRect(for platform: GamePlatform) -> CGRect {
        let amplitude = platform.patrolAmplitude
        guard amplitude > 0 else { return blockRect(at: platform.position) }
        let centre = CGPoint(x: platform.patrolCenterX, y: platform.position.y)
        return blockRect(at: centre).insetBy(dx: -amplitude, dy: 0)
    }

    /// Full-bounds AABB check against every existing block (expanded by
    /// the placement margin) and any already-planned positions.
    private func isFreePosition(_ center: CGPoint, planned: [CGPoint] = []) -> Bool {
        let candidate = blockRect(at: center)
        for platform in platforms {
            let expanded = sweptRect(for: platform)
                .insetBy(dx: -placementMargin, dy: -placementMargin)
            if candidate.intersects(expanded) { return false }
        }
        for point in planned {
            let expanded = blockRect(at: point)
                .insetBy(dx: -placementMargin, dy: -placementMargin)
            if candidate.intersects(expanded) { return false }
        }
        return true
    }

    // MARK: Route validation (graph / BFS)

    /// Time-of-flight based horizontal reach for a jump that must rise `rise`.
    private func horizontalReach(rise: CGFloat, launch: CGFloat) -> CGFloat {
        let disc = launch * launch + 2 * gravity * max(0, rise)
        guard disc > 0 else { return 0 }
        let time = (launch + disc.squareRoot()) / -gravity
        return maxHorizontalSpeed * time * 0.7 + tileSize.width / 2
    }

    /// True when a safe route exists from the bottom springboard to
    /// `target` using ONLY: the springboard, neutral platforms, resolved
    /// and retired platforms. Active wrong answers are excluded — a wrong
    /// answer must never be a required stepping stone.
    private func routeExists(toPosition target: CGPoint) -> Bool {
        let climbRise = maxJumpHeight * jumpSafetyFactor
        let springboardRise = (springboardVelocity * springboardVelocity / (2 * -gravity)) * jumpSafetyFactor

        // Directly from the springboard (full width → dx is never limiting).
        if target.y - springboardY <= springboardRise { return true }

        let nodes = platforms.filter { !$0.isActiveAnswer }.map(\.position)
        var reached = [Bool](repeating: false, count: nodes.count)
        var queue: [Int] = []

        func canHop(from a: CGPoint, to b: CGPoint, rise: CGFloat, launch: CGFloat, fullWidthStart: Bool = false) -> Bool {
            let dy = b.y - a.y
            guard dy <= rise else { return false }
            if fullWidthStart { return true }
            return wrapDx(a.x, b.x) <= horizontalReach(rise: dy, launch: launch)
        }

        for (index, node) in nodes.enumerated()
        where node.y - springboardY <= springboardRise {
            reached[index] = true
            queue.append(index)
        }
        while let index = queue.popLast() {
            let from = nodes[index]
            if canHop(from: from, to: target, rise: climbRise, launch: bounceVelocity) { return true }
            for (next, node) in nodes.enumerated()
            where !reached[next] && canHop(from: from, to: node, rise: climbRise, launch: bounceVelocity) {
                reached[next] = true
                queue.append(next)
            }
        }
        return false
    }

    /// A wrong block may not sit in the natural approach path to the
    /// correct block (the corridor below/next to it), so the player never
    /// lands on one almost automatically during a correct jump.
    private func blocksApproach(toCorrect correct: CGPoint, candidate: CGPoint) -> Bool {
        let dx = wrapDx(correct.x, candidate.x)
        let below = correct.y - candidate.y
        return dx < correctApproachWidth
            && below > -correctApproachAbove
            && below < correctApproachBelow
    }

    /// A correct block needs a genuinely clear landing corridor. This keeps
    /// neutral platforms as well as answer choices away from its approach.
    private func hasClearApproach(toCorrect candidate: CGPoint, planned: [CGPoint] = []) -> Bool {
        !platforms.contains { blocksApproach(toCorrect: candidate, candidate: $0.position) }
            && !planned.contains { blocksApproach(toCorrect: candidate, candidate: $0) }
    }

    /// Enforces real air between answer blocks (planned + already active),
    /// so a jump aimed at one answer can never clip a neighbouring answer.
    private func farFromOtherAnswers(_ candidate: CGPoint, planned: [CGPoint],
                                     separation: CGFloat? = nil) -> Bool {
        let minimum = separation ?? minAnswerSeparation
        let others = planned + platforms.filter(\.isActiveAnswer).map(\.position)
        return others.allSatisfy { other in
            let dx = wrapDx(candidate.x, other.x)
            let dy = candidate.y - other.y
            return (dx * dx + dy * dy).squareRoot() >= minimum
        }
    }

    // MARK: Answer set generation (fixed order, atomic activation)

    /// Fixed order: question → correct value → place correct block within
    /// safe distance → validate a route WITHOUT wrong blocks → place wrong
    /// blocks outside the route corridor → overlap/margins/reachability
    /// already guaranteed per placement → activate everything at once.
    private func buildAnswerSet() {
        // Tapping the equation only reveals its result. During that tutorial
        // transition the answer tiles remain in their existing colours; they
        // are made inert, not greyed out like an obsolete question set.
        if tutorial.isActive, tutorial.currentStep == 7,
           preserveAnswerAppearanceAfterTutorialReveal {
            for platform in platforms where platform.isActiveAnswer {
                platform.deactivateKeepingAppearance()
            }
            return
        }

        // Step 5 is the immediate follow-up to the compulsory wrong answer.
        // Its green answer remains a live answer until it is actually landed
        // on.  A delayed/duplicate refresh must never supersede that group:
        // doing so made the briefly green correct block turn grey and caused
        // the player to bounce off it as if it were an ordinary stone.
        if tutorial.isActive, tutorial.currentStep == 5,
           let correct = platforms.first(where: {
               $0.isActiveAnswer && $0.value == state.correctAnswer
           }) {
            correct.styleAsActiveAnswer(theme: theme, isCorrect: true, helperEnabled: true)
            return
        }

        // `buildAnswerSet()` is normally reached exactly once per question.
        // SpriteKit/SwiftUI can nevertheless deliver an extra layout or scene
        // lifecycle callback while the opening field is being attached.  Do
        // not turn that into a second visible group for the same question
        // (for example two `5 × 1` answer blocks at the start of table 5).
        // The prompt check is what makes this precise: without it, a leftover
        // wrong block whose value happens to equal the NEXT question's answer
        // was mistaken for an already-built group, so the previous set was
        // never greyed out and that stale block silently became the answer.
        // Tutorial steps deliberately rebuild individual teaching groups, so
        // their flow remains governed by the cases below.
        if !tutorial.isActive,
           answerSetPrompt == state.questionText,
           platforms.contains(where: {
               $0.isActiveAnswer && $0.value == state.correctAnswer
           }) {
            return
        }

        // The old set is superseded: values, positions and sizes stay
        // exactly as they are; only their answer function is switched off.
        for platform in platforms where platform.isActiveAnswer {
            platform.markSuperseded(theme: theme)
        }
        answerSetPrompt = state.questionText

        // Lessons 1–2 are intentionally answer-free.  The remaining guided
        // sets are minimal and deterministic: exactly the object the lesson
        // asks the child to use, never a random obstacle.
        if tutorial.isActive {
            switch tutorial.currentStep {
            case 1, 2, 7, 9, 10:
                return
            case 3:
                activateTutorialAnswers(correct: true, wrongCount: 0, showCorrect: false,
                                       requiresUpcomingSpawn: true)
                return
            case 4:
                activateTutorialAnswers(correct: false, wrongCount: 1, showCorrect: false)
                return
            case 5:
                activateTutorialAnswers(correct: true, wrongCount: 3, showCorrect: true)
                return
            case 6:
                if tutorialAwaitingQuestionTap { return }
                activateTutorialAnswers(correct: true, wrongCount: 1, showCorrect: false)
                return
            case 8 where tutorial.triplerAnswerPending:
                activateTutorialAnswers(correct: true, wrongCount: 0, showCorrect: false,
                                       requiresUpcomingSpawn: true)
                return
            case 8:
                return
            case 11:
                buildTutorialStarSet()
                return
            default:
                break
            }
        }

        let correctValue = state.correctAnswer
        setsBuilt += 1

        // Variable group size: 2–5 blocks in total, so the layout never
        // settles into a predictable "always 1 or always 5" rhythm.
        var targetWrong = Int.random(in: max(1, wrongAnswerCount - 2)...wrongAnswerCount)

        // Occasional skip set: only wrong answers in the first band, the
        // correct block one band higher (with, usually, one wrong companion
        // so a lone block is never a guaranteed correct answer). Retried a
        // few times so the roll reliably produces a real skip set.
        if setsBuilt > 2, !lastSetWasSkip, Double.random(in: 0...1) < skipSetChance {
            for _ in 0..<3 {
                guard let skip = buildSkipLayout(correctValue: correctValue) else { continue }
                lastSetWasSkip = true
                activateAnswerSet(correct: skip.correct, wrongs: skip.wrongs)
                return
            }
        }
        lastSetWasSkip = false

        // Reserve a strip below the group when a firework should ride
        // along (it must sit clearly UNDER the answer group). A firework
        // set always gets a real group: at least two wrong blocks.
        let planEliminator = eliminatorsSpawned < maxEliminatorsPerRun
            && setsBuilt > 2
            && answersSinceSpecial >= specialCooldown
            && Double.random(in: 0...1) < eliminatorChance
        if planEliminator { targetWrong = max(2, targetWrong) }
        let offset: CGFloat = planEliminator ? eliminatorRaise : 0

        // A correct block with fewer than two wrong options is a weak
        // layout: retry with a fresh position, and only accept the best
        // attempt so far when every retry stays crowded.
        var bestLayout: (CGPoint, [(String, CGPoint)])?
        for _ in 0..<3 {
            guard let correctPos = findCorrectPosition(offset: offset),
                  routeExists(toPosition: correctPos) else { continue }

            var planned: [CGPoint] = [correctPos]
            var wrongs = placeWrongs(correct: correctPos, planned: &planned,
                                     count: targetWrong, offset: offset)
            if wrongs.count >= min(2, targetWrong) {
                if !planEliminator {
                    addDecoyIfLucky(correct: correctPos, planned: &planned, wrongs: &wrongs)
                }
                activateAnswerSet(correct: (correctValue, correctPos), wrongs: wrongs)
                if planEliminator {
                    placeEliminator(correct: correctPos, group: planned)
                }
                return
            }
            if wrongs.count >= (bestLayout?.1.count ?? -1) {
                bestLayout = (correctPos, wrongs)
            }
        }
        if let (correctPos, wrongs) = bestLayout {
            activateAnswerSet(correct: (correctValue, correctPos), wrongs: wrongs)
            return
        }

        // Guaranteed minimal fallback: correct block on a spot that is
        // freed up if necessary, plus whatever wrong blocks still fit.
        let pos = guaranteedCorrectPosition()
        var planned: [CGPoint] = [pos]
        let wrongs = placeWrongs(correct: pos, planned: &planned, count: targetWrong)
        activateAnswerSet(correct: (correctValue, pos), wrongs: wrongs)
    }


    /// Places up to `count` wrong blocks. Two passes inside the position
    /// finder (strict, then slightly relaxed) keep the correct answer from
    /// ending up alone.
    private func placeWrongs(correct: CGPoint?, planned: inout [CGPoint],
                             count: Int, offset: CGFloat = 0) -> [(String, CGPoint)] {
        var wrongs: [(String, CGPoint)] = []
        // Question sources may occasionally contain the same distractor more
        // than once. A visible answer group must never repeat an option.
        var uniqueValues: [String] = []
        for value in state.question.distractors where value != state.correctAnswer && !uniqueValues.contains(value) {
            uniqueValues.append(value)
        }
        var values = uniqueValues.shuffled()
        while wrongs.count < count, !values.isEmpty {
            guard let pos = findWrongPosition(correct: correct, planned: planned,
                                              offset: offset) else { break }
            planned.append(pos)
            wrongs.append((values.removeFirst(), pos))
        }
        return wrongs
    }

    /// Sometimes one extra wrong block floats well above the group. This
    /// breaks the tell that a block standing on its own must be correct.
    private func addDecoyIfLucky(correct: CGPoint, planned: inout [CGPoint],
                                 wrongs: inout [(String, CGPoint)]) {
        guard Double.random(in: 0...1) < decoyChance,
              let pos = findWrongPosition(correct: correct, planned: planned,
                                          offset: skipSetRaise) else { return }
        let used = Set([state.correctAnswer] + wrongs.map(\.0))
        planned.append(pos)
        wrongs.append((state.distractor(excluding: used), pos))
    }

    /// Layout for a skip set: at least two wrong answers in the normal
    /// band, the correct block in the raised band with a validated route —
    /// usually joined there by one wrong companion, so the raised pair
    /// still requires real calculation instead of "the lone one is right".
    private func buildSkipLayout(correctValue: String)
        -> (correct: (String, CGPoint), wrongs: [(String, CGPoint)])? {
        var planned: [CGPoint] = []
        var wrongs: [(String, CGPoint)] = []
        var values = state.question.distractors.shuffled()
        while wrongs.count < max(2, wrongAnswerCount), !values.isEmpty {
            guard let pos = findWrongPosition(correct: nil, planned: planned) else { break }
            planned.append(pos)
            wrongs.append((values.removeFirst(), pos))
        }
        guard wrongs.count >= 2,
              let correctPos = findCorrectPosition(planned: planned, offset: skipSetRaise),
              routeExists(toPosition: correctPos) else { return nil }
        planned.append(correctPos)
        if Double.random(in: 0...1) < 0.6, !values.isEmpty,
           let pos = findWrongPosition(correct: correctPos, planned: planned,
                                       offset: skipSetRaise) {
            planned.append(pos)
            wrongs.append((values.removeFirst(), pos))
        }
        return ((correctValue, correctPos), wrongs)
    }

    /// Puts the firework on a stone in the strip BELOW the (raised) answer
    /// group — the player meets it first, then the group it can disarm.
    /// First choice is an EXISTING empty stone in that strip (guaranteed
    /// valid, so the firework reliably appears); only when none exists is
    /// a new stone created.
    private func placeEliminator(correct: CGPoint, group: [CGPoint]) {
        guard group.count >= 3, let minY = group.map(\.y).min() else { return }
        let top = minY - 90
        // Existing stones may sit INSIDE the visible screen (from just above
        // the player up): the star sparkles in early, well before the wrong
        // answers scroll into view — you can already shoot them down while
        // they are still entering at the top.
        let visibleBottom = max(springboardY + 140, player.position.y + 140)
        guard top > visibleBottom else { return }

        // Prefer the LOWEST suitable stone: seen soonest, visible longest.
        let existing = platforms
            .filter { $0.role == .neutralPlatform && $0.powerup == nil
                && $0.position.y > visibleBottom && $0.position.y < top }
            .min { $0.position.y < $1.position.y }
        if let stone = existing {
            stone.attachPowerup(.eliminator, theme: theme)
            eliminatorsSpawned += 1
            answersSinceSpecial = 0
            return
        }

        // Creating a NEW stone must stay above the viewport (no pop-in).
        let spawnBottom = size.height + 40
        guard top > spawnBottom else { return }
        for _ in 0..<48 {
            let candidate = CGPoint(x: .random(in: tileEdgeInset...(size.width - tileEdgeInset)),
                                    y: .random(in: spawnBottom...top))
            if isFreePosition(candidate), !blocksApproach(toCorrect: correct, candidate: candidate) {
                let platform = GamePlatform(role: .neutralPlatform, size: tileSize)
                platform.position = candidate
                platform.styleAsNeutral(theme: theme)
                platform.attachPowerup(.eliminator, theme: theme)
                addChild(platform)
                platforms.append(platform)
                eliminatorsSpawned += 1
                answersSinceSpecial = 0
                return
            }
        }
    }

    /// Spawn zone for answer blocks: fully ABOVE the visible viewport
    /// (bottom edge of a block clears viewportTop + spawnMargin), so new
    /// blocks only come into view through natural player movement.
    private func answerWindowYRange(offset: CGFloat = 0) -> ClosedRange<CGFloat> {
        let lower = size.height + spawnMargin + tileSize.height / 2 + offset
        return lower...(lower + 240)
    }

    /// Y-samples are weighted toward the BOTTOM of the window, so answer
    /// blocks come into view as soon as the spawn rule allows — this keeps
    /// the option-free climb between two questions as short as possible.
    private func answerY(in range: ClosedRange<CGFloat>) -> CGFloat {
        let t = pow(CGFloat.random(in: 0...1), 1.7)
        return range.lowerBound + t * (range.upperBound - range.lowerBound)
    }

    private func findCorrectPosition(planned: [CGPoint] = [], offset: CGFloat = 0) -> CGPoint? {
        let yRange = answerWindowYRange(offset: offset)
        for _ in 0..<80 {
            let candidate = CGPoint(x: .random(in: tileEdgeInset...(size.width - tileEdgeInset)),
                                    y: answerY(in: yRange))
            if isFreePosition(candidate, planned: planned),
               hasClearApproach(toCorrect: candidate, planned: planned),
               farFromOtherAnswers(candidate, planned: planned) { return candidate }
        }
        return nil
    }

    /// `correct` may be nil for skip sets, where wrong blocks are placed
    /// before the (raised) correct block exists. Two passes: strict
    /// separation, then slightly relaxed with a taller window, so a set
    /// rarely ends up with fewer than two wrong options.
    private func findWrongPosition(correct: CGPoint?, planned: [CGPoint],
                                   offset: CGFloat = 0) -> CGPoint? {
        let base = answerWindowYRange(offset: offset)
        for relaxed in [false, true] {
            let yRange = relaxed ? base.lowerBound...(base.upperBound + 100) : base
            let separation = relaxed ? minAnswerSeparation * 0.75 : minAnswerSeparation
            for _ in 0..<40 {
                let candidate = CGPoint(x: .random(in: tileEdgeInset...(size.width - tileEdgeInset)),
                                        y: relaxed ? .random(in: yRange) : answerY(in: yRange))
                if let correct, blocksApproach(toCorrect: correct, candidate: candidate) { continue }
                if isFreePosition(candidate, planned: planned),
                   farFromOtherAnswers(candidate, planned: planned, separation: separation) {
                    return candidate
                }
            }
        }
        return nil
    }

    /// Grid-scan for a free spot; as a last resort a non-answer block in
    /// the window is removed to make room. Always returns a valid position.
    private func guaranteedCorrectPosition() -> CGPoint {
        let yRange = answerWindowYRange()
        var y = yRange.lowerBound
        while y <= yRange.upperBound {
            var x = tileEdgeInset
            while x <= size.width - tileEdgeInset {
                let candidate = CGPoint(x: x, y: y)
                if isFreePosition(candidate), hasClearApproach(toCorrect: candidate) { return candidate }
                x += max(90, tileSize.width + placementMargin)
            }
            y += 60
        }
        // Free up a spot: recycle the position of a non-answer block that
        // is still outside the viewport (removing it is never visible).
        if let victim = platforms.first(where: { !$0.isActiveAnswer && yRange.contains($0.position.y) }) {
            let position = victim.position
            victim.removeFromParent()
            platforms.removeAll { $0 === victim }
            return position
        }
        return CGPoint(x: size.width / 2, y: yRange.lowerBound)
    }

    /// The complete, validated set becomes active in ONE update — brand
    /// new block instances, existing blocks are never reused or relabeled.
    private func activateAnswerSet(correct: (String, CGPoint), wrongs: [(String, CGPoint)]) {
#if DEBUG
        // A new block must never be created (partially) inside the viewport.
        for position in [correct.1] + wrongs.map(\.1) {
            let bottom = position.y - tileSize.height / 2
            if bottom < size.height + spawnMargin - 1 {
                assertionFailure("Spawn: answer block created inside the visible spawn margin at \(position)")
            }
        }
#endif
        let correctBlock = GamePlatform(role: .answer, value: correct.0, size: tileSize)
        correctBlock.position = correct.1
        // Redemption: after a mistake the next correct block shows in
        // helper green until the player lands on it (wrongs stay normal).
        correctBlock.styleAsActiveAnswer(theme: theme, isCorrect: true,
                                         helperEnabled: helperEnabled || redemptionArmed)
        addChild(correctBlock)
        platforms.append(correctBlock)

        for (value, position) in wrongs {
            let block = GamePlatform(role: .answer, value: value, size: tileSize)
            block.position = position
            block.styleAsActiveAnswer(theme: theme, isCorrect: false, helperEnabled: helperEnabled)
            addChild(block)
            platforms.append(block)
        }
        debugValidateLayout()
    }

    private func activateTutorialAnswers(correct: Bool, wrongCount: Int, showCorrect: Bool,
                                         requiresUpcomingSpawn: Bool = false) {
        // Prefer the normal validated spawn position.  If the current device
        // layout has not produced a full route yet, put the lesson directly
        // above the player instead of creating an unreachable off-screen tile.
        let correctPosition = requiresUpcomingSpawn
            ? (findCorrectPosition() ?? guaranteedCorrectPosition())
            : tutorialAnswerPosition()
        if correct {
            let block = GamePlatform(role: .answer, value: state.correctAnswer, size: tileSize)
            block.position = correctPosition
            block.styleAsActiveAnswer(theme: theme, isCorrect: true, helperEnabled: showCorrect)
            addChild(block); platforms.append(block)
        }
        var planned = [correctPosition]
        for value in state.question.distractors.prefix(wrongCount) {
            guard let position = findWrongPosition(correct: correct ? correctPosition : nil, planned: planned) else { continue }
            planned.append(position)
            let block = GamePlatform(role: .answer, value: value, size: tileSize)
            block.position = position
            block.styleAsActiveAnswer(theme: theme, isCorrect: false, helperEnabled: false)
            addChild(block); platforms.append(block)
        }
    }

    /// Finds a free nearby fallback when the normal above-screen route is not
    /// ready. This prevents a tutorial tile from being created on a stone.
    private func tutorialAnswerPosition() -> CGPoint {
        if let candidate = findCorrectPosition(), routeExists(toPosition: candidate) {
            return candidate
        }
        let horizontalOffsets: [CGFloat] = [0, -92, 92, -184, 184]
        let verticalOffsets: [CGFloat] = [145, 190, 235, 280]
        for yOffset in verticalOffsets {
            for xOffset in horizontalOffsets {
                let candidate = CGPoint(x: min(max(tileEdgeInset, player.position.x + xOffset), size.width - tileEdgeInset),
                                        y: player.position.y + yOffset)
                if isFreePosition(candidate), hasClearApproach(toCorrect: candidate) {
                    return candidate
                }
            }
        }
        return guaranteedCorrectPosition()
    }

    /// Deferred switch to the next question: HUD and blocks change together,
    /// after the confirmation, never in the landing frame.
    private func performQuestionAdvance() {
        state.advanceQuestion()
        buildAnswerSet()
    }

    /// Watchdog repair: only acts when the correct block has scrolled off
    /// the BOTTOM of the screen (it was never landed on). The invisible
    /// old block is removed off-screen — no visible status change — and a
    /// brand-new correct block is placed in the spawn zone above the
    /// viewport, so it comes into view naturally. Blocks are NEVER
    /// restyled because of distance, height or approach.
    private func ensureCorrectReachable() {
        guard !hasActiveCorrectPlatform() else { return }
        // Remove actives that dropped below the screen (invisible anyway).
        for platform in platforms
        where platform.isActiveAnswer && platform.position.y < -20 {
            platform.removeFromParent()
        }
        platforms.removeAll { $0.isActiveAnswer && $0.position.y < -20 }

        guard !hasActiveCorrectPlatform() else { return }
        // Before the first tutorial success (and after the star), do not
        // turn a missed good block into a mixed answer group. A fresh good
        // block is placed above the screen until the player gets it.
        let onlyCorrectUntilCollected = awaitingCorrectAfterTutorialStar
            || (tutorial.isActive && (tutorial.currentStep == 3
                || (tutorial.currentStep == 8 && tutorial.triplerAnswerPending)))
        if onlyCorrectUntilCollected {
            let position = findCorrectPosition() ?? guaranteedCorrectPosition()
            activateAnswerSet(correct: (state.correctAnswer, position), wrongs: [])
            return
        }
        // Step 4 deliberately contains only the required wrong answer, and
        // step 6 stops tiles after a correct answer until the question is
        // tapped. The watchdog must not inject a normal answer group there.
        if tutorial.isActive,
           tutorial.currentStep == 4 || (tutorial.currentStep == 6 && tutorialAwaitingQuestionTap) {
            return
        }
        if let pos = findCorrectPosition(), routeExists(toPosition: pos) {
            // The repaired set also gets wrong options again, so a missed
            // correct block never degrades into a lone-answer stretch.
            var planned: [CGPoint] = [pos]
            let wrongs = placeWrongs(correct: pos, planned: &planned, count: wrongAnswerCount)
            activateAnswerSet(correct: (state.correctAnswer, pos), wrongs: wrongs)
        } else {
            activateAnswerSet(correct: (state.correctAnswer, guaranteedCorrectPosition()), wrongs: [])
        }
    }

    /// Step 4 must remain completable when the player jumps past its single
    /// wrong answer. Replace it only once it has left the screen; the new
    /// tile uses the normal safe spawn window above the viewport.
    private func ensureRequiredTutorialWrongAnswer() {
        guard tutorial.isActive, tutorial.currentStep == 4 else { return }
        guard !platforms.contains(where: { $0.isActiveAnswer && $0.value != state.correctAnswer }) else {
            return
        }
        let position = findCorrectPosition() ?? guaranteedCorrectPosition()
        guard let value = state.question.distractors.first(where: { $0 != state.correctAnswer }) else {
            return
        }
        let block = GamePlatform(role: .answer, value: value, size: tileSize)
        block.position = position
        block.styleAsActiveAnswer(theme: theme, isCorrect: false, helperEnabled: false)
        addChild(block)
        platforms.append(block)
    }

    /// The correct block "exists" as long as it is anywhere on or above
    /// the screen — the player can always drop down (springboard) or climb
    /// up to it. No proximity window, so passing it never changes anything.
    private func hasActiveCorrectPlatform() -> Bool {
        platforms.contains {
            $0.isActiveAnswer && $0.value == state.correctAnswer && $0.position.y > -20
        }
    }

    // MARK: Debug validation

    /// Development-time checks: overlap, uniform height, exactly one
    /// active correct answer, and a wrong-answer-free route.
    private func debugValidateLayout() {
#if DEBUG
        if tutorial.isActive { return }
        for (i, a) in platforms.enumerated() {
            for b in platforms[(i + 1)...] {
                let rectA = sweptRect(for: a)
                let rectB = sweptRect(for: b)
                if rectA.intersects(rectB) {
                    assertionFailure("Layout: blocks overlap at \(a.position) / \(b.position)")
                }
            }
        }
        let activeCorrect = platforms.filter { $0.isActiveAnswer && $0.value == state.correctAnswer }
        if activeCorrect.count != 1 {
            assertionFailure("Layout: expected exactly 1 active correct block, found \(activeCorrect.count)")
        }
        if let correct = activeCorrect.first, !routeExists(toPosition: correct.position) {
            // Never terminate a player's run because a development invariant
            // reports a transient layout issue. The deterministic route spine
            // above prevents this in normal generation; retain a diagnostic
            // for development without turning it into a user-visible crash.
            print("Layout warning: no wrong-answer-free route to the correct block")
        }
#endif
    }

    // MARK: Neutral platform spawning (while climbing)

    private func addNeutralPlatform(at position: CGPoint, allowMoving: Bool = true) {
        let platform = GamePlatform(role: .neutralPlatform, size: tileSize)
        platform.position = position
        platform.styleAsNeutral(theme: theme)
        addChild(platform)
        platforms.append(platform)
        attachTutorialPickupIfNeeded(to: platform)

        // ~10% of the plain in-between stones patrol slowly side to side.
        // Answer blocks NEVER move (their placement guarantees stay exact);
        // landing detection reads live positions, so patrol "just works".
        guard allowMoving, !tutorial.isActive, CGFloat.random(in: 0...1) < 0.10 else { return }
        // Bound the amplitude so the stone's ENTIRE swept range stays clear
        // of the screen edges AND every neighbour — validated before it ever
        // starts moving, so `sweptRect` (and thus every overlap check) holds.
        let amplitude = maxPatrolAmplitude(for: platform, desired: 36)
        guard amplitude > 22 else { return }
        platform.beginPatrol(amplitude: amplitude,
                             duration: Double.random(in: 1.2...1.9))
    }

    /// Largest patrol amplitude (≤ `desired`) for which the stone's full
    /// left-right sweep stays inside the screen and clear of every other
    /// block's own swept range, honouring `placementMargin`. Returns 0 when
    /// even a small patrol would collide, in which case the stone stays put.
    private func maxPatrolAmplitude(for platform: GamePlatform, desired: CGFloat) -> CGFloat {
        // Screen-edge limit (blocks keep 44 pt off each wall).
        var limit = min(platform.position.x - 44,
                        size.width - 44 - platform.position.x,
                        desired)
        guard limit > 0 else { return 0 }

        // Neighbour limit: for any block sharing our vertical band, the two
        // swept ranges (ours + theirs) plus a full block width and margin
        // must fit between the spawn centres at closest approach.
        let vBand = tileSize.height + placementMargin
        let needed = tileSize.width + placementMargin
        for other in platforms where other !== platform {
            guard abs(other.position.y - platform.position.y) < vBand else { continue }
            let otherCentreX = other.patrolAmplitude > 0 ? other.patrolCenterX
                                                         : other.position.x
            let dx = abs(otherCentreX - platform.position.x)
            limit = min(limit, dx - other.patrolAmplitude - needed)
        }
        return max(0, limit)
    }

    /// Bands are prepared up to `spawnAheadBuffer` above the viewport, so
    /// even at the highest climb speed blocks exist long before they come
    /// into view — nothing ever pops in visibly.
    private func spawnPlatformsIfNeeded() {
        while nextSpawnY < size.height + spawnAheadBuffer {
            spawnBand(at: nextSpawnY)
            nextSpawnY += CGFloat.random(in: minBandGap...maxBandGap)
        }
    }

    /// One band = usually one neutral platform, sometimes two. Every
    /// position is overlap-validated BEFORE the platform is added; there
    /// is no visible correction afterwards.
    private func spawnBand(at y: CGFloat) {
        let count = CGFloat.random(in: 0...1) < 0.4 ? 2 : 1
        let edgeInset = tileEdgeInset
        let maxSafeStep: CGFloat = 180
        var addedRouteStone = false

        // The route stone is generated first. Its vertical gap is already
        // bounded by `minBandGap...maxBandGap`; keeping its x distance bounded
        // makes the graph route deterministic on every device width.
        for _ in 0..<32 {
            let x = min(max(edgeInset, routeAnchorX + .random(in: -maxSafeStep...maxSafeStep)),
                        size.width - edgeInset)
            let candidate = CGPoint(x: x, y: y + CGFloat.random(in: -bandJitter...bandJitter))
            if isFreePosition(candidate),
               !platforms.contains(where: { platform in
                   platform.isActiveAnswer && blocksApproach(toCorrect: platform.position, candidate: candidate)
               }) {
                addNeutralPlatform(at: candidate)
                routeAnchorX = x
                addedRouteStone = true
                break
            }
        }

        // An optional second stone remains random decoration; gameplay never
        // depends on it for reachability.
        guard addedRouteStone else { return }
        for _ in 1..<count {
            for _ in 0..<12 {
                let candidate = CGPoint(x: .random(in: tileEdgeInset...(size.width - tileEdgeInset)),
                                        y: y + CGFloat.random(in: -bandJitter...bandJitter))
                if isFreePosition(candidate),
                   !platforms.contains(where: { platform in
                       platform.isActiveAnswer && blocksApproach(toCorrect: platform.position, candidate: candidate)
                   }) {
                    addNeutralPlatform(at: candidate)
                    break
                }
            }
        }
    }

    // MARK: Game loop

    override func update(_ currentTime: TimeInterval) {
        guard started, !state.isGameOver else { return }
        // Frozen for the intro card: keep the clock in sync (so there's no dt
        // jump when it resumes) but advance no physics.
        if isFrozen {
            lastUpdateTime = currentTime
            return
        }
        if lastUpdateTime == 0 { lastUpdateTime = currentTime }
        let dt = CGFloat(min(1.0 / 30.0, currentTime - lastUpdateTime))
        lastUpdateTime = currentTime

        updateHorizontal(dt: dt)
        if tutorial.isActive && tutorial.currentStep == 1 {
            tutorialMovedLeft = tutorialMovedLeft || player.position.x < tutorialStartX - 45
            tutorialMovedRight = tutorialMovedRight || player.position.x > tutorialStartX + 45
            if (tutorialMovedLeft || tutorialMovedRight), tutorialMovementConfirmedAt == nil {
                tutorialMovementConfirmedAt = currentTime
            }
            if tutorialMovedLeft, tutorialMovedRight,
               let confirmedAt = tutorialMovementConfirmedAt,
               currentTime - confirmedAt >= 2 { completeTutorialStep(1) }
        }

        // Vertical physics.
        let previousBottom = player.position.y - playerHalfHeight
        velocityY += gravity * dt
        player.position.y += velocityY * dt

        if velocityY < 0 {
            checkLanding(previousBottom: previousBottom)
        }

        // Permanent bottom springboard: catches the player across the FULL
        // width (the check ignores x, so wrapping can't create a gap) and
        // relaunches automatically with the extra-high "super" bounce —
        // this is the only place that behavior exists.
        if velocityY < 0 && player.position.y - playerHalfHeight <= springboardY + 8 {
            velocityY = springboardVelocity
            squashTimer = 0.14
            bounceSpring()
            springboard.run(.sequence([
                .scaleY(to: 0.6, duration: 0.06),
                .scaleY(to: 1.0, duration: 0.12)
            ]))
        }

        // Deferred answer refresh (after the correct-answer confirmation).
        if let refreshAt = answerRefreshAt, currentTime >= refreshAt {
            answerRefreshAt = nil
            performQuestionAdvance()
        }

        // Watchdog: keep the correct answer inside the playable window.
        if !tutorialSuppressesAnswerTiles,
           answerRefreshAt == nil, currentTime - lastReachabilityCheck > 0.5 {
            lastReachabilityCheck = currentTime
            ensureCorrectReachable()
            ensureRequiredTutorialWrongAnswer()
        }

        collectTouchedPowerups()
        refreshMissedTutorialPickup()
        updatePlayerAppearance(dt: dt)
        scrollIfNeeded()
        spawnPlatformsIfNeeded()
        cullPlatforms()
    }

    /// Pickups are collected by TOUCH: brushing the floating icon while
    /// flying past (up or down) is enough — no landing required. This also
    /// makes the −1 hazard a real obstacle to steer around.
    private func collectTouchedPowerups() {
        for platform in platforms where platform.powerup != nil {
            let iconY = platform.position.y + tileSize.height / 2 + 18
            if wrapDx(player.position.x, platform.position.x) < playerHalfWidth + 14,
               abs(player.position.y - iconY) < playerHalfHeight + 24,
               let collected = platform.takePowerup() {
                let origin = platform.convert(collected.localOrigin, to: self)
                apply(powerup: collected.type, origin: origin)
            }
        }
    }

    /// Tilt-first steering with touch fallback, smoothed for easy control.
    private func updateHorizontal(dt: CGFloat) {
        var desired: CGFloat = 0
        if let targetX {
            desired = (targetX - player.position.x) * 9
        } else if let tilt = currentTilt, abs(tilt) >= tiltDeadZone {
            let magnitude = CGFloat(pow(Double(abs(tilt)), 1.25)) * tiltSensitivity
            desired = tilt < 0 ? -magnitude : magnitude
            if abs(tilt - lastReportedTilt) > 0.08 {
                lastReportedTilt = tilt
                PlaytimeTracker.shared.registerInteraction()
            }
        }
        desired = min(max(desired, -maxHorizontalSpeed), maxHorizontalSpeed)
        velocityX += (desired - velocityX) * min(1, dt * 9)
        player.position.x += velocityX * dt

        // Horizontal screen wrapping: leave one side, appear on the other.
        // Velocity and all state stay untouched; at most one wrap per frame.
        let half = playerHalfWidth
        if player.position.x > size.width + half {
            player.position.x -= size.width + 2 * half
        } else if player.position.x < -half {
            player.position.x += size.width + 2 * half
        }
    }

    /// Squash & stretch, lean, and facing — the jump cycle.
    private func updatePlayerAppearance(dt: CGFloat) {
        if squashTimer > 0 { squashTimer -= dt }

        let speedFactor = min(1, abs(velocityY) / 1100)
        let targetScaleY: CGFloat
        let targetScaleX: CGFloat
        if squashTimer > 0 {
            targetScaleY = 0.72
            targetScaleX = 1.18
        } else {
            targetScaleY = 1 + 0.16 * speedFactor
            targetScaleX = 1 - 0.10 * speedFactor
        }
        let blend = min(1, dt * 18)
        currentScaleY += (targetScaleY - currentScaleY) * blend
        currentScaleX += (targetScaleX - currentScaleX) * blend

        if velocityX > 60 { facing = -1 } else if velocityX < -60 { facing = 1 }
        playerSprite.xScale = facing * currentScaleX
        playerSprite.yScale = currentScaleY

        let targetRotation = -velocityX * 0.0004
        player.zRotation += (targetRotation - player.zRotation) * min(1, dt * 10)
    }

    /// Spring compress-then-extend on every bounce (anticipation + lift-off).
    private func bounceSpring() {
        // Every character's artwork includes its own coil, so the separate
        // drawn spring stays hidden. Skip the per-bounce action allocation
        // entirely when it isn't visible.
        guard !springNode.isHidden else { return }
        springNode.removeAllActions()
        springNode.yScale = 1
        springNode.run(.sequence([
            .scaleY(to: 0.45, duration: 0.06),
            .scaleY(to: 1.30, duration: 0.10),
            .scaleY(to: 1.0, duration: 0.12)
        ]))
    }

    // MARK: Landing

    private func checkLanding(previousBottom: CGFloat) {
        let bottom = player.position.y - playerHalfHeight
        let halfWidth = tileSize.width / 2
        let halfHeight = tileSize.height / 2

        for platform in platforms {
            let top = platform.position.y + halfHeight
            guard previousBottom >= top - 2, bottom <= top else { continue }
            let dx = abs(player.position.x - platform.position.x)
            guard dx < halfWidth + 6 else { continue }

            velocityY = bounceVelocity
            squashTimer = 0.14
            bounceSpring()

            // While the next answer set is pending, the old set is closed:
            // landings are plain bounces, never a second registration.
            if platform.isActiveAnswer && answerRefreshAt == nil {
                if platform.value == state.correctAnswer {
                    // The correct block registers over its full (generous)
                    // landing width — a deliberate jump is always rewarded.
                    landedCorrect(on: platform)
                } else {
                    // Any landing that bounces off a wrong block counts as
                    // wrong. If the player touches it enough to spring back
                    // up, it registers as a wrong answer (deduction) — no
                    // silent edge-graze forgiveness.
                    landedWrong(on: platform)
                }
            } else if tutorial.isActive && tutorial.currentStep == 2 {
                completeTutorialStep(2)
            }
            return
        }
    }

    /// Flow: register once → checkmark INSIDE the block → block stays an
    /// ordinary platform (number, position, size unchanged) → the NEXT
    /// set is built later, validated, and activated in one update.
    private func landedCorrect(on platform: GamePlatform) {
        // The first tutorial point gets one explicit, visual explanation of
        // where trophies are counted. Later answers stay pleasantly quick.
        let isFirstTutorialTrophy = tutorial.isActive && tutorial.currentStep == 3
        let shouldRetryTutorialStar = tutorial.isActive && tutorial.currentStep == 11
        let trophyOrigin = platform.position
        platform.resolveCorrect(theme: theme)
        haptic(success: true)
        PlaytimeTracker.shared.registerInteraction()
        let wasTripled = state.triplerArmed
        state.answeredCorrectly()
        // The star lesson ends only after this remaining good answer is
        // used; from this point ordinary answer groups may resume.
        awaitingCorrectAfterTutorialStar = false
        if isFirstTutorialTrophy {
            flyTutorialTrophyToHUD(from: trophyOrigin)
        }
        if tutorial.isActive {
            switch tutorial.currentStep {
            case 3, 5: completeTutorialStep(tutorial.currentStep)
            case 6: tutorialAwaitingQuestionTap = true
            case 8 where tutorial.triplerAnswerPending: completeTutorialStep(8)
            default: break
            }
        }
        // A consumed tripler flies to the trophy score; an unarmed state
        // just makes sure no stray aura lingers. Redemption ends here too.
        if wasTripled {
            consumeTriplerVisual()
        } else {
            setTriplerVisual(false)
        }
        redemptionArmed = false
        // At a 4-answer streak, retract any ×3 coin the player hasn't seen yet
        // (still above the viewport) so arming it can't coincide with the jump
        // that triggers the 5-in-a-row bonus. A coin already on screen is left
        // alone — yanking a visible pickup would feel unfair. New ×3 spawns are
        // suppressed at this streak too (see maybeSpawnPickups).
        if state.correctStreak == 4 {
            for platform in platforms where platform.powerup == .tripler
                && platform.position.y > size.height {
                platform.removePowerup()
            }
        }
        answersSinceSpecial += 1
        maybeSpawnPickups()
        // Short confirmation beat: long enough to see the checkmark, short
        // enough that the next set spawns before the player climbs far —
        // every extra tenth here directly lengthens the option-free gap.
        // A good answer during the star lesson does not complete that lesson.
        // Refresh promptly into a new group with a fresh star above screen,
        // so the player can never strand the tutorial by taking the answer
        // before touching the star.
        answerRefreshAt = lastUpdateTime + (shouldRetryTutorialStar ? 0.18 : 0.4)
    }

    /// Register once → cross INSIDE the block → nothing else changes.
    private func landedWrong(on platform: GamePlatform) {
        platform.resolveWrong()
        haptic(success: false)
        PlaytimeTracker.shared.registerInteraction()
        let hadTripler = state.triplerArmed
        state.answeredWrong()
        if tutorial.isActive && tutorial.currentStep == 4 { completeTutorialStep(4) }
        // A wrong answer forfeits an armed tripler: the bubble visibly pops.
        if hadTripler {
            popTriplerVisual()
        } else {
            setTriplerVisual(false)
        }
        // …and arms redemption: the next correct block turns green
        // (including the one of the CURRENT question) until it is landed on.
        if !helperEnabled, !state.isGameOver {
            redemptionArmed = true
            highlightCorrectForRedemption()
        }
    }

    // MARK: Powerups

    /// Rolled once per correct answer, with independent chances so pickups
    /// feel genuinely random — but never more than ONE special per roll and
    /// with a shared cooldown, so specials spread out instead of clustering.
    private func maybeSpawnPickups() {
        guard !tutorial.isActive else { return }
        guard !state.isGameOver, answersSinceSpecial >= specialCooldown else { return }
        // Hearts: only in a lives game, only when they can actually heal —
        // half hearts from 1 lost heart, full hearts from 2 lost hearts.
        if !state.isEndless, let lost = state.lostLifeHalves,
           Double.random(in: 0...1) < heartChance {
            let type: PowerupType? = lost >= 4
                ? (Double.random(in: 0...1) < 0.4 ? .fullHeart : .halfHeart)
                : (lost >= 2 ? .halfHeart : nil)
            if let type, attachPowerupToUpcomingNeutral(type) {
                answersSinceSpecial = 0
                return
            }
        }
        // ×3 tripler: capped per run and never once the goal is within reach
        // (a ×3 that would overshoot the final trophy is just noise). During an
        // active streak it appears half as often (a ×3 is already very strong
        // when every trophy doubles), and it is suppressed entirely at a
        // 4-answer streak so it can never be armed for the very jump that
        // triggers the 5-in-a-row bonus — those two rewards should not collide.
        let triplerChanceNow = state.isStreakActive ? triplerChance * 0.5 : triplerChance
        if triplersSpawned < maxTriplersPerRun,
           state.correctStreak != 4,
           state.score <= runTrophyGoal - 2,
           !state.isEndless,
           Double.random(in: 0...1) < triplerChanceNow,
           attachPowerupToUpcomingNeutral(.tripler) {
            triplersSpawned += 1
            answersSinceSpecial = 0
            return
        }
        // −1 hazard: only once the player has real trophies to spare (20+).
        if minusOnesSpawned < maxMinusOnesPerRun,
           state.score >= minusOneScoreThreshold, !state.isEndless,
           Double.random(in: 0...1) < minusOneChance,
           attachPowerupToUpcomingNeutral(.minusOne) {
            minusOnesSpawned += 1
            answersSinceSpecial = 0
        }
    }

    /// Called by the SwiftUI equation badge.  It does not freeze the scene;
    /// it merely releases the next part of the lesson after a real tap.
    func tutorialQuestionWasTapped() {
        guard tutorial.isActive, tutorial.currentStep == 6 else { return }
        preserveAnswerAppearanceAfterTutorialReveal = true
        tutorialAwaitingQuestionTap = false
        completeTutorialStep(6)
    }

    private func completeTutorialStep(_ step: Int) {
        guard tutorial.isActive, tutorial.currentStep == step else { return }
        tutorial.complete(step: step, helperEnabled: helperEnabled)
        if step == 1 && tutorial.currentStep == 2 {
            tutorial.complete(step: 2, helperEnabled: helperEnabled)
        }
        if step == 9 && tutorial.currentStep == 10 {
            // The old recovery-heart lesson was intentionally removed.
            tutorial.complete(step: 10, helperEnabled: helperEnabled)
        }
        tutorialHeartCount = 0
        tutorialNextPickupAt = 0
        if step == 1 {
            // Release the first real stones only once the movement lesson is
            // complete.  This is deliberately before the next answer set.
            spawnPlatformsIfNeeded()
        }
        if tutorial.currentStep == 9 {
            // Start the −1 lesson only on stones still above the viewport.
            // The player should have a fair chance to see and avoid it.
            for platform in platforms where platform.role == .neutralPlatform
                && platform.powerup == nil && platform.position.y > size.height + 40 {
                platform.attachPowerup(.minusOne, theme: theme)
            }
        }
        // Let the current bounce/confirmation finish, then build the next
        // guided set above the viewport.
        answerRefreshAt = max(answerRefreshAt ?? 0, lastUpdateTime + 0.18)
        ensureTutorialPickup()
    }

    private var tutorialRequiredPickup: PowerupType? {
        guard tutorial.isActive else { return nil }
        switch tutorial.currentStep {
        case 7: return tutorialHeartCount == 0 ? .halfHeart : .fullHeart
        case 8: return tutorial.triplerAnswerPending ? nil : .tripler
        case 9: return .minusOne
        case 11: return .eliminator
        default: return nil
        }
    }

    private func attachTutorialPickupIfNeeded(to platform: GamePlatform) {
        guard let type = tutorialRequiredPickup, platform.powerup == nil else { return }
        // Step 11 places its single star together with its answer group.
        // Adding it from every spawned neutral stone created duplicate stars.
        guard type != .eliminator else { return }
        // Only the −1 lesson intentionally populates every suitable stone.
        // Hearts, the tripler and the star are one-at-a-time and reappear
        // only after the player has missed the previous one.
        if type != .minusOne,
           platforms.contains(where: { $0 !== platform && $0.powerup == type }) { return }
        platform.attachPowerup(type, theme: theme, fillsRightHalf: nextHeartHalfIsRight)
    }

    private func ensureTutorialPickup() {
        guard lastUpdateTime >= tutorialNextPickupAt else { return }
        guard let type = tutorialRequiredPickup else { return }
        guard type != .eliminator else { return }
        if !platforms.contains(where: { $0.powerup == type }) {
            _ = attachPowerupToUpcomingNeutral(type)
        }
    }

    /// Uses the same placement logic as the normal in-game star: a proper
    /// answer group is spawned above the viewport and the star sits on a
    /// reachable stone directly beneath it.
    private func buildTutorialStarSet() {
        for platform in platforms where platform.powerup == .eliminator {
            platform.removePowerup()
        }
        // Raise the whole group so the star gets its own visible runway below
        // it, rather than sitting immediately underneath a wrong answer.
        let tutorialStarRaise: CGFloat = 100
        let correct = findCorrectPosition(offset: tutorialStarRaise) ?? guaranteedCorrectPosition()
        var planned = [correct]
        let wrongs = placeWrongs(correct: correct, planned: &planned, count: 2,
                                 offset: tutorialStarRaise)
        activateAnswerSet(correct: (state.correctAnswer, correct), wrongs: wrongs)
        placeTutorialStarAboveViewport(below: correct)
    }

    private func placeTutorialStarAboveViewport(below answer: CGPoint) {
        // The regular answer margin is intentionally roomy. The mandatory
        // tutorial star needs to arrive much sooner after −1, while its stone
        // must still be entirely outside the visible viewport.
        let tutorialStarInset: CGFloat = 12
        let minimumY = size.height + tileSize.height / 2 + tutorialStarInset
        let maximumY = answer.y - 80
        guard maximumY > minimumY else { return }
        let candidate = platforms
            .filter { $0.role == .neutralPlatform && $0.powerup == nil
                && $0.position.y >= minimumY && $0.position.y <= maximumY }
            .min { $0.position.y < $1.position.y }
        if let candidate {
            candidate.attachPowerup(.eliminator, theme: theme)
            return
        }
        // If no prepared stone is available, create the star near the bottom
        // of its valid strip so it enters view shortly before the answers.
        let earlyTop = min(maximumY, minimumY + 48)
        for _ in 0..<40 {
            let position = CGPoint(x: .random(in: tileEdgeInset...(size.width - tileEdgeInset)),
                                   y: .random(in: minimumY...earlyTop))
            if isFreePosition(position), !blocksApproach(toCorrect: answer, candidate: position) {
                let stone = GamePlatform(role: .neutralPlatform, size: tileSize)
                stone.position = position
                stone.styleAsNeutral(theme: theme)
                stone.attachPowerup(.eliminator, theme: theme)
                addChild(stone)
                platforms.append(stone)
                return
            }
        }
    }

    /// The tutorial star belongs below the answer pair, so the player can
    /// collect it before reaching the wrong answer it is meant to remove.
    private func placeTutorialStar(below answer: CGPoint) {
        for platform in platforms where platform.powerup == .eliminator {
            platform.removePowerup()
        }
        let candidate = platforms
            .filter { $0.role == .neutralPlatform && $0.powerup == nil
                && $0.position.y > player.position.y + 55
                && $0.position.y < answer.y - 70 }
            .min { $0.position.y < $1.position.y }
        if let candidate {
            candidate.attachPowerup(.eliminator, theme: theme)
            return
        }
        let y = max(player.position.y + 150, answer.y - 130)
        for _ in 0..<24 {
            let position = CGPoint(x: .random(in: tileEdgeInset...(size.width - tileEdgeInset)), y: y)
            if isFreePosition(position) {
                let stone = GamePlatform(role: .neutralPlatform, size: tileSize)
                stone.position = position
                stone.styleAsNeutral(theme: theme)
                stone.attachPowerup(.eliminator, theme: theme)
                addChild(stone)
                platforms.append(stone)
                return
            }
        }
    }

    /// A missed mandatory pickup is retried promptly. Once the player has
    /// passed it, retire the icon and put a replacement on the lowest
    /// upcoming neutral stone instead of waiting for distant culling.
    private func refreshMissedTutorialPickup() {
        guard tutorial.isActive, let required = tutorialRequiredPickup else { return }
        // A star remains available until it scrolls out naturally; removing
        // it merely because the player briefly jumped over it felt unfair.
        if required == .eliminator {
            ensureTutorialStar()
            return
        }
        for platform in platforms where platform.powerup == required
            // A near miss may still be collected on the downward arc. Only
            // replace a pickup once it is well below the player.
            && platform.position.y < -40 {
            platform.removePowerup()
        }
        ensureTutorialPickup()
    }

    /// The star is mandatory. If a preceding answer refresh had no suitable
    /// stone at that exact moment, retry placement against the current group
    /// until one is available. `placeTutorialStarAboveViewport` guarantees
    /// the icon is attached only to an off-screen stone.
    private func ensureTutorialStar() {
        guard tutorial.isActive, tutorial.currentStep == 11 else { return }
        guard !platforms.contains(where: { $0.powerup == .eliminator }) else { return }
        guard let correct = platforms.first(where: {
            $0.isActiveAnswer && $0.value == state.correctAnswer
        }) else { return }
        placeTutorialStarAboveViewport(below: correct.position)
    }

    private func handleTutorialPowerup(_ powerup: PowerupType) {
        guard tutorial.isActive else { return }
        switch (tutorial.currentStep, powerup) {
        case (7, .halfHeart):
            tutorialHeartCount = 1
            // Do not show the next heart while this heart is still flying to
            // the HUD; that previously read as a doubled collection effect.
            tutorialNextPickupAt = lastUpdateTime + 0.75
        case (7, .fullHeart):
            completeTutorialStep(7)
        case (8, .tripler):
            tutorial.setTriplerAnswerPending(true)
            answerRefreshAt = max(answerRefreshAt ?? 0, lastUpdateTime + 0.18)
        case (9, .minusOne):
            for other in platforms where other.powerup == .minusOne { other.removePowerup() }
            completeTutorialStep(9)
        case (11, .eliminator):
            // The firework removes all wrong options. Keep the remaining
            // correct tile as the sole answer even after the tutorial itself
            // has formally completed.
            awaitingCorrectAfterTutorialStar = true
            completeTutorialStep(11)
            // Keep the cleared answer group clear. A normal new group only
            // starts after the remaining good answer has been used.
            answerRefreshAt = nil
        default: break
        }
    }

    /// Attaches a pickup to an empty stone that is still ABOVE the viewport
    /// (so it never pops into view) and not already carrying one. The lowest
    /// candidate wins: that is the first stone the player will meet.
    @discardableResult
    private func attachPowerupToUpcomingNeutral(_ type: PowerupType) -> Bool {
        let candidate = platforms
            .filter { $0.role == .neutralPlatform && $0.powerup == nil
                && $0.position.y > size.height + 40 }
            .min { $0.position.y < $1.position.y }
        guard let platform = candidate else { return false }
        platform.attachPowerup(type, theme: theme, fillsRightHalf: nextHeartHalfIsRight)
        return true
    }

    /// Hearts fill left half first (exactly like the HUD row), so with an
    /// odd number of half-lives the RIGHT half of a heart is open next.
    private var nextHeartHalfIsRight: Bool {
        (state.livesHalves ?? 0) % 2 == 1
    }

    // MARK: HUD anchors (scene coordinates)

    /// SwiftUI reports the actual rendered HUD rectangles after layout. Cache
    /// their scene-coordinate centres so flight effects never drift when the
    /// HUD asset size, score width or device layout changes.
    private var renderedTrophyHUDPoint: CGPoint?
    private var renderedHeartHUDPoints: [Int: CGPoint] = [:]
    /// A fallback point is fine for ordinary effects, but the first tutorial
    /// trophy must wait for a window-backed conversion so its lesson clearly
    /// lands in the score HUD on every iPad configuration.
    private var hasResolvedTrophyHUDTarget = false

    /// Input rectangles are in the containing window's coordinate space.
    /// `SKScene.convertPoint(fromView:)` handles the SKView's actual bounds,
    /// scale and coordinate flip, which is more accurate than recreating
    /// those rules from a SwiftUI GeometryReader.
    func setHUDTargets(trophy: CGRect?, hearts: [Int: CGRect], viewSize: CGSize) {
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        var usedWindowCoordinates = false
        func scenePoint(for rect: CGRect) -> CGPoint {
#if os(iOS)
            if let skView = view, let window = skView.window {
                usedWindowCoordinates = true
                let viewPoint = skView.convert(CGPoint(x: rect.midX, y: rect.midY), from: window)
                return convertPoint(fromView: viewPoint)
            }
#endif
            // Before the scene has been attached to an SKView, keep the
            // previous scale-based fallback. It is replaced on first layout.
            return CGPoint(x: rect.midX * size.width / viewSize.width,
                           y: size.height - rect.midY * size.height / viewSize.height)
        }
        renderedTrophyHUDPoint = trophy.map(scenePoint)
        hasResolvedTrophyHUDTarget = trophy != nil && usedWindowCoordinates
        renderedHeartHUDPoints = hearts.mapValues(scenePoint)
    }

    /// Vertical centre of the HUD top row, derived from the real safe-area
    /// inset of the view so it matches every device precisely.
    private var hudRowY: CGFloat {
        let safeTop = view?.safeAreaInsets.top ?? 44
        // top padding (8) + half the common 28 pt HUD asset below the safe
        // area. This remains the fallback until SwiftUI reports its anchors.
        return size.height - safeTop - 8 - GameHUDMetrics.assetSize / 2
    }

    /// Centre of the specific heart the pickup will fill. Mirrors the
    /// SwiftUI layout: three 28 pt hearts, 2 pt spacing, right-aligned
    /// with 16 pt padding; hearts fill left-to-right, left half first.
    private func heartHUDPoint(fillsRight: Bool) -> CGPoint {
        let heartWidth = GameHUDMetrics.assetSize
        let spacing = GameHUDMetrics.heartSpacing
        let index = min(2, max(0, (state.livesHalves ?? 0) / 2))
        if let rendered = renderedHeartHUDPoints[index] {
            return CGPoint(x: rendered.x + (fillsRight ? heartWidth * 0.22 : -heartWidth * 0.22),
                           y: rendered.y)
        }
        let rightEdge = size.width - GameHUDMetrics.horizontalPadding
        let centerX = rightEdge - CGFloat(2 - index) * (heartWidth + spacing) - heartWidth / 2
        return CGPoint(x: centerX + (fillsRight ? heartWidth * 0.22 : -heartWidth * 0.22), y: hudRowY)
    }

    /// Centre of the trophy icon, which sits just right of the score number
    /// in the centred score cluster (number width scales with its digits).
    private var trophyHUDPoint: CGPoint {
        if let renderedTrophyHUDPoint { return renderedTrophyHUDPoint }
        let digits = CGFloat(String(state.score).count)
        let textHalfWidth = digits * 7.5
        let trophyOffset = textHalfWidth + 3 + GameHUDMetrics.assetSize / 2
        return CGPoint(x: size.width / 2 + trophyOffset, y: hudRowY)
    }

    /// A smooth arc from a pickup to its HUD element: quadratic curve that
    /// bows slightly upward, eased at both ends.
    private func curvedFlight(from: CGPoint, to: CGPoint, duration: TimeInterval) -> SKAction {
        let path = CGMutablePath()
        path.move(to: from)
        let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        let control = CGPoint(x: mid.x - (to.x - from.x) * 0.12, y: mid.y + 46)
        path.addQuadCurve(to: to, control: control)
        let follow = SKAction.follow(path, asOffset: false, orientToPath: false, duration: duration)
        follow.timingMode = .easeInEaseOut
        return follow
    }

    /// Small expanding ring where a flight lands on its HUD element.
    private func arrivalPing(at point: CGPoint, color: SKColor) {
        let ring = SKShapeNode(circleOfRadius: 10)
        ring.strokeColor = color
        ring.lineWidth = 3
        ring.fillColor = .clear
        ring.position = point
        ring.zPosition = 51
        ring.alpha = 0.9
        addChild(ring)
        ring.run(.sequence([
            .group([.scale(to: 2.2, duration: 0.3), .fadeOut(withDuration: 0.3)]),
            .removeFromParent()
        ]))
    }

    private func apply(powerup: PowerupType, origin: CGPoint) {
        switch powerup {
        case .halfHeart:
            flyHeartToHUD(from: origin, halves: 1)
        case .fullHeart:
            flyHeartToHUD(from: origin, halves: 2)
        case .eliminator:
            launchFirework(from: origin)
        case .tripler:
            state.armTripler()
            setTriplerVisual(true)
        case .minusOne:
            flyMinusOneToScore(from: origin)
        }
        if powerup == .halfHeart || powerup == .fullHeart {
            heartHaptic()
        } else {
            haptic(success: powerup != .minusOne)
        }
        PlaytimeTracker.shared.registerInteraction()
        handleTutorialPowerup(powerup)
    }

    /// The −1 hazard: a red bubble arcs to the trophy score and takes the
    /// trophy exactly on arrival, so the loss is as legible as the ×3 gain.
    private func flyMinusOneToScore(from origin: CGPoint) {
        let target = trophyHUDPoint
        let bubble = makeBubbleIcon(text: "−1", fill: GameColors.wrongRed)
        bubble.position = origin
        bubble.zPosition = 50
        addChild(bubble)
        bubble.run(.sequence([
            .group([curvedFlight(from: origin, to: target, duration: 0.5),
                    .sequence([.scale(to: 1.25, duration: 0.2),
                               .scale(to: 0.8, duration: 0.3)])]),
            .run { [weak self] in
                guard let self else { return }
                self.state.loseTrophy()
                self.arrivalPing(at: target, color: GameColors.wrongRed)
            },
            .group([.scale(to: 0.15, duration: 0.15), .fadeOut(withDuration: 0.15)]),
            .removeFromParent()
        ]))
    }

    /// Bubble builder shared with the ×3 visuals (instance-level so it can
    /// be reused by pop/fly effects with any colour).
    private func makeBubbleIcon(text: String, fill: SKColor) -> SKShapeNode {
        let bubble = SKShapeNode(circleOfRadius: 15)
        bubble.fillColor = fill
        bubble.strokeColor = .white
        bubble.lineWidth = 2
        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.text = text
        label.fontSize = 14
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.zPosition = 1
        bubble.addChild(label)
        return bubble
    }

    /// The collected heart lifts off its stone and arcs to the EXACT heart
    /// (and half) it will fill in the HUD row; the heal lands at the moment
    /// of arrival, so the HUD heart fills right where the flight ends.
    private func flyHeartToHUD(from origin: CGPoint, halves: Int) {
        let fillsRight = nextHeartHalfIsRight
        let target = heartHUDPoint(fillsRight: fillsRight)
        let heart = GamePlatform.makeHeartIcon(theme: theme, half: halves == 1,
                                               fillsRightHalf: fillsRight)
        heart.position = origin
        heart.zPosition = 50
        addChild(heart)
        // `makeHeartIcon` is 22 points wide, while the HUD heart can be
        // larger on iPad. Finish at its rendered size before SwiftUI swaps in
        // the real HUD glyph, avoiding a visible size drop at arrival.
        let hudHeartScale = GameHUDMetrics.assetSize / 22
        heart.run(.sequence([
            .group([curvedFlight(from: origin, to: target, duration: 0.55),
                    .sequence([.scale(to: hudHeartScale * 1.15, duration: 0.2),
                               .scale(to: hudHeartScale, duration: 0.35)])]),
            .run { [weak self] in
                guard let self else { return }
                self.state.gainLifeHalves(halves)
                self.arrivalPing(at: target, color: self.theme.skDeep)
            },
            .group([.scale(to: 0.3, duration: 0.15), .fadeOut(withDuration: 0.15)]),
            .removeFromParent()
        ]))
    }

    /// The star fires a SHOOTING STAR at every active wrong answer: a small
    /// theme-coloured star races along a gently curved arc (with a fading
    /// streak behind it) and the block pops only on impact. The blocks stop
    /// counting as answers immediately (a landing during the animation is a
    /// plain bounce), but they stay visible until they are hit — even when
    /// they are still above the visible screen.
    private func launchFirework(from origin: CGPoint) {
        let targets = platforms.filter { $0.isActiveAnswer && $0.value != state.correctAnswer }

        // Small radial burst at the pickup itself — also the fallback when
        // there happens to be nothing to disarm.
        for i in 0..<6 {
            let angle = CGFloat(i) / 6 * 2 * .pi
            let dot = SKShapeNode(circleOfRadius: 3)
            dot.fillColor = theme.skPrimary
            dot.strokeColor = .clear
            dot.position = origin
            dot.zPosition = 40
            addChild(dot)
            dot.run(.sequence([
                .group([.move(by: CGVector(dx: cos(angle) * 34, dy: sin(angle) * 34), duration: 0.3),
                        .fadeOut(withDuration: 0.3)]),
                .removeFromParent()
            ]))
        }

        for (index, block) in targets.enumerated() {
            block.retireForElimination()
            let delay = 0.05 + 0.11 * Double(index)
            // Use coordinate conversion rather than assuming the platform is
            // a direct scene child; the ray then remains exact if its parent
            // hierarchy changes during a future layout refinement.
            let target = block.convert(CGPoint.zero, to: self)

            // A gently bowed arc; alternate the bow side per star so a
            // volley fans out instead of overlapping.
            let side: CGFloat = index.isMultiple(of: 2) ? 1 : -1
            let dx = target.x - origin.x
            let dy = target.y - origin.y
            let distance = max(1, (dx * dx + dy * dy).squareRoot())
            let mid = CGPoint(x: (origin.x + target.x) / 2, y: (origin.y + target.y) / 2)
            let control = CGPoint(x: mid.x + (-dy / distance) * side * distance * 0.22,
                                  y: mid.y + (dx / distance) * side * distance * 0.22)
            let arc = CGMutablePath()
            arc.move(to: origin)
            arc.addQuadCurve(to: target, control: control)

            // The fading streak that traces the arc.
            let line = SKShapeNode(path: arc)
            line.strokeColor = theme.skPrimary
            line.lineWidth = 3
            line.lineCap = .round
            line.fillColor = .clear
            line.alpha = 0
            line.zPosition = 40
            addChild(line)
            line.run(.sequence([
                .wait(forDuration: delay),
                .fadeAlpha(to: 0.6, duration: 0.08),
                .fadeOut(withDuration: 0.32),
                .removeFromParent()
            ]))

            // The shooting star itself: a spinning theme-coloured star that
            // follows the arc; impact pops the block with a small ping.
            let star = GamePlatform.makeStarIcon(theme: theme, radius: 8)
            star.fillColor = theme.skPrimary
            star.strokeColor = .white
            star.lineWidth = 1
            star.position = origin
            star.zPosition = 41
            star.alpha = 0
            addChild(star)
            let travelTime = 0.22 + Double(distance) / 2200
            let travel = SKAction.follow(arc, asOffset: false, orientToPath: false,
                                         duration: travelTime)
            travel.timingMode = .easeIn
            star.run(.sequence([
                .wait(forDuration: delay),
                .fadeIn(withDuration: 0.05),
                .group([travel, .rotate(byAngle: .pi * 3, duration: travelTime)]),
                .run { [weak self, weak block] in
                    guard let self, let block else { return }
                    self.arrivalPing(at: block.position, color: self.theme.skPrimary)
                    block.run(.sequence([
                        .group([.scale(to: 0.1, duration: 0.25),
                                .fadeOut(withDuration: 0.25)]),
                        .removeFromParent()
                    ]))
                    self.platforms.removeAll { $0 === block }
                },
                .group([.scale(to: 2.0, duration: 0.16), .fadeOut(withDuration: 0.16)]),
                .removeFromParent()
            ]))
        }
    }

    /// After a mistake, the correct block of the current question is shown
    /// in helper green right away (new sets get the green via activation).
    private func highlightCorrectForRedemption() {
        guard redemptionArmed, !helperEnabled else { return }
        platforms.first { $0.isActiveAnswer && $0.value == state.correctAnswer }?
            .styleAsActiveAnswer(theme: theme, isCorrect: true, helperEnabled: true)
    }

    /// Pulsing aura in the THEME colour + a ×3 badge above the character
    /// while the tripler is armed; removed the instant it is spent or lost.
    private func setTriplerVisual(_ on: Bool) {
        triplerAura?.removeFromParent()
        triplerAura = nil
        guard on else { return }
        let aura = SKNode()
        let glow = SKShapeNode(circleOfRadius: 46)
        glow.fillColor = theme.skPrimary.withAlphaComponent(0.20)
        glow.strokeColor = theme.skPrimary.withAlphaComponent(0.55)
        glow.lineWidth = 2
        glow.run(.repeatForever(.sequence([
            .scale(to: 1.12, duration: 0.5),
            .scale(to: 1.0, duration: 0.5)
        ])))
        aura.addChild(glow)
        let badge = SKShapeNode(circleOfRadius: 15)
        badge.fillColor = theme.skPrimary
        badge.strokeColor = .white
        badge.lineWidth = 2
        let badgeLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        badgeLabel.text = "×3"
        badgeLabel.fontSize = 14
        badgeLabel.fontColor = .white
        badgeLabel.verticalAlignmentMode = .center
        badgeLabel.zPosition = 1
        badge.addChild(badgeLabel)
        badge.position = CGPoint(x: 0, y: 60)
        badge.run(.repeatForever(.sequence([
            .scale(to: 1.15, duration: 0.35),
            .scale(to: 1.0, duration: 0.35)
        ])))
        aura.addChild(badge)
        aura.zPosition = -1
        player.addChild(aura)
        triplerAura = aura
    }

    /// One reusable ×3 bubble node (same look as the armed badge).
    private func makeTriplerBubble(radius: CGFloat) -> SKShapeNode {
        let bubble = SKShapeNode(circleOfRadius: radius)
        bubble.fillColor = theme.skPrimary
        bubble.strokeColor = .white
        bubble.lineWidth = 2
        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.text = "×3"
        label.fontSize = radius * 0.95
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.zPosition = 1
        bubble.addChild(label)
        return bubble
    }

    /// On the tripled answer the ×3 bubble detaches and arcs to the trophy
    /// icon at the top, shrinking INTO it with an arrival ping — the player
    /// sees exactly where the double points land.
    private func consumeTriplerVisual() {
        triplerAura?.removeFromParent()
        triplerAura = nil
        let origin = CGPoint(x: player.position.x, y: player.position.y + 46)
        let target = trophyHUDPoint
        let bubble = makeTriplerBubble(radius: 16)
        bubble.position = origin
        bubble.zPosition = 50
        addChild(bubble)
        bubble.run(.sequence([
            .group([curvedFlight(from: origin, to: target, duration: 0.55),
                    .sequence([.scale(to: 1.3, duration: 0.22),
                               .scale(to: 0.75, duration: 0.33)])]),
            .run { [weak self] in
                guard let self else { return }
                self.arrivalPing(at: target, color: self.theme.skPrimary)
            },
            .group([.scale(to: 0.15, duration: 0.15), .fadeOut(withDuration: 0.15)]),
            .removeFromParent()
        ]))
    }

    /// Once, on the first tutorial answer, a trophy flies from the exact
    /// centre of the answered block to the score icon. It deliberately uses
    /// the same flight, timing and arrival treatment as the ×3 reward.
    private func flyTutorialTrophyToHUD(from origin: CGPoint) {
        // The first tutorial reward can happen immediately after the HUD is
        // shown. Wait for its real SwiftUI anchor rather than falling back to
        // a size-based estimate, which is visibly off on iPad.
        guard hasResolvedTrophyHUDTarget, let target = renderedTrophyHUDPoint else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                self?.flyTutorialTrophyToHUD(from: origin)
            }
            return
        }
        let trophy = makeTutorialTrophyIcon(height: tileSize.height)
        trophy.position = origin
        trophy.zPosition = 50
        addChild(trophy)
        trophy.run(.sequence([
            .group([curvedFlight(from: origin, to: target, duration: 0.55),
                    .sequence([.scale(to: 1.3, duration: 0.22),
                               .scale(to: 0.75, duration: 0.33)])]),
            .run { [weak self] in
                guard let self else { return }
                self.arrivalPing(at: target, color: self.theme.skPrimary)
            },
            .group([.scale(to: 0.15, duration: 0.15), .fadeOut(withDuration: 0.15)]),
            .removeFromParent()
        ]))
    }

    /// Small vector trophy, tinted with the active character theme. The
    /// enclosing node is exactly as high as a regular answer block.
    private func makeTutorialTrophyIcon(height: CGFloat) -> SKNode {
        let trophy = SKNode()
        let scale = height / 24
        trophy.setScale(scale)

        let cupPath = CGMutablePath()
        cupPath.move(to: CGPoint(x: -8, y: 11))
        cupPath.addLine(to: CGPoint(x: 8, y: 11))
        cupPath.addLine(to: CGPoint(x: 6, y: 1))
        cupPath.addQuadCurve(to: CGPoint(x: 0, y: -4), control: CGPoint(x: 4, y: -3))
        cupPath.addQuadCurve(to: CGPoint(x: -6, y: 1), control: CGPoint(x: -4, y: -3))
        cupPath.closeSubpath()
        let cup = SKShapeNode(path: cupPath)
        cup.fillColor = theme.skPrimary
        cup.strokeColor = .white
        cup.lineWidth = 1.5
        trophy.addChild(cup)

        for direction: CGFloat in [-1, 1] {
            let handlePath = CGMutablePath()
            handlePath.move(to: CGPoint(x: direction * 7, y: 8))
            handlePath.addQuadCurve(to: CGPoint(x: direction * 12, y: 2),
                                    control: CGPoint(x: direction * 13, y: 8))
            handlePath.addQuadCurve(to: CGPoint(x: direction * 7, y: 0),
                                    control: CGPoint(x: direction * 11, y: -1))
            let handle = SKShapeNode(path: handlePath)
            handle.strokeColor = .white
            handle.lineWidth = 1.5
            handle.lineCap = .round
            trophy.addChild(handle)
        }

        let stem = SKShapeNode(rectOf: CGSize(width: 4, height: 5), cornerRadius: 1)
        stem.fillColor = theme.skPrimary
        stem.strokeColor = .white
        stem.lineWidth = 1.2
        stem.position.y = -6
        trophy.addChild(stem)

        let base = SKShapeNode(rectOf: CGSize(width: 12, height: 3), cornerRadius: 1.5)
        base.fillColor = theme.skPrimary
        base.strokeColor = .white
        base.lineWidth = 1.2
        base.position.y = -10
        trophy.addChild(base)
        return trophy
    }

    /// A wrong answer with the ×3 armed: the bubble POPS on the spot —
    /// a quick over-inflate, a burst of shards, gone. Losing the tripler
    /// is unmistakable.
    private func popTriplerVisual() {
        triplerAura?.removeFromParent()
        triplerAura = nil
        let center = CGPoint(x: player.position.x, y: player.position.y + 46)
        let bubble = makeTriplerBubble(radius: 15)
        bubble.position = center
        bubble.zPosition = 50
        addChild(bubble)
        bubble.run(.sequence([
            .scale(to: 1.4, duration: 0.09),
            .group([.scale(to: 1.9, duration: 0.08), .fadeOut(withDuration: 0.08)]),
            .removeFromParent()
        ]))
        for i in 0..<8 {
            let angle = CGFloat(i) / 8 * 2 * .pi
            let shard = SKShapeNode(circleOfRadius: 3)
            shard.fillColor = theme.skPrimary
            shard.strokeColor = .clear
            shard.position = center
            shard.zPosition = 49
            addChild(shard)
            shard.run(.sequence([
                .wait(forDuration: 0.12),
                .group([.move(by: CGVector(dx: cos(angle) * 42, dy: sin(angle) * 42), duration: 0.32),
                        .fadeOut(withDuration: 0.32)]),
                .removeFromParent()
            ]))
        }
    }

    // MARK: Feedback

    private func haptic(success: Bool) {
#if os(iOS)
        feedbackGenerator.notificationOccurred(success ? .success : .error)
        // Re-arm the engine so the following landing is warm too.
        feedbackGenerator.prepare()
#endif
    }

    private func heartHaptic() {
#if os(iOS)
        heartFeedbackGenerator.impactOccurred()
        heartFeedbackGenerator.prepare()
#endif
    }

    /// The soft tap for using the answer hint. Called by the SwiftUI equation
    /// badge; re-arms itself so every later use stays warm too.
    func hintHaptic() {
#if os(iOS)
        hintFeedbackGenerator.impactOccurred()
        hintFeedbackGenerator.prepare()
#endif
    }

    /// Warms the answer-hint generator just before it's needed. Called when the
    /// tutorial reaches the "tap the question mark" step, so the very first tap
    /// lands on an already-warm Taptic Engine instead of paying the cold-start.
    func prepareHintHaptic() {
#if os(iOS)
        hintFeedbackGenerator.prepare()
#endif
    }

    // MARK: Scrolling

    private func scrollIfNeeded() {
        let threshold = size.height * 0.55
        guard player.position.y > threshold else { return }
        let dy = player.position.y - threshold
        player.position.y = threshold
        totalClimb += dy
        for platform in platforms {
            platform.position.y -= dy
        }
        nextSpawnY -= dy
    }

    private func cullPlatforms() {
        let cutoff: CGFloat = -60
        platforms.removeAll { platform in
            if platform.position.y < cutoff {
                platform.removeFromParent()
                return true
            }
            return false
        }
    }

    // MARK: Input (touch fallback — tilt is primary on device)

    private func steer(toX x: CGFloat) {
        targetX = x
        PlaytimeTracker.shared.registerInteraction()
    }

#if canImport(UIKit)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        steer(toX: touch.location(in: self).x)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        steer(toX: touch.location(in: self).x)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        targetX = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        targetX = nil
    }
#endif

#if os(macOS)
    override func mouseDown(with event: NSEvent) {
        steer(toX: event.location(in: self).x)
    }

    override func mouseDragged(with event: NSEvent) {
        steer(toX: event.location(in: self).x)
    }

    override func mouseUp(with event: NSEvent) {
        targetX = nil
    }
#endif
}
