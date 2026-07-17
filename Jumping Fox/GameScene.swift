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
    static let neutralFill = SKColor(white: 1.0, alpha: 0.95)
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

    let blockID = UUID()          // stable identity — never an array index
    let role: Role
    let value: String             // immutable after init
    private let shape: SKShapeNode
    private let label: SKLabelNode
    private let statusIcon: SKLabelNode
    private(set) var status: Status
    private(set) var hasBeenTriggered = false

    var isActiveAnswer: Bool { role == .answer && status == .active }

    init(role: Role, value: String = "") {
        self.role = role
        self.value = value
        self.status = role == .answer ? .active : .neutralResolved

        // Status icon INSIDE the block bounds (top-right corner), part of
        // the node itself: it moves with camera/wrapping, never affects
        // collision or size, and is empty while the block is active.
        statusIcon = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        statusIcon.fontSize = 11
        statusIcon.verticalAlignmentMode = .center
        statusIcon.horizontalAlignmentMode = .center
        statusIcon.position = CGPoint(x: Self.platformSize.width / 2 - 11, y: 3)
        statusIcon.zPosition = 1
        statusIcon.text = ""

        shape = SKShapeNode(rectOf: Self.platformSize, cornerRadius: Self.platformSize.height / 2)
        shape.lineWidth = 2

        label = SKLabelNode(fontNamed: "AvenirNext-Bold")
        label.text = value
        label.fontSize = value.count >= 5 ? 13 : (value.count == 4 ? 15 : 18)
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center

        super.init()
        addChild(shape)
        if role == .answer {
            addChild(label)
            addChild(statusIcon)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Styling (never changes value, position or size)

    func styleAsNeutral(theme: AnimalCharacter) {
        shape.fillColor = GameColors.neutralFill
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

    /// Landed correct: register once, keep number/position/size, show ONLY
    /// a checkmark inside the block. No overlays, no scaling, no movement.
    func resolveCorrect(theme: AnimalCharacter) {
        guard status == .active else { return }
        status = .correctResolved
        hasBeenTriggered = true
        styleAsNeutral(theme: theme)
        label.fontColor = theme.skDeep
        label.alpha = 0.45
        statusIcon.text = "✓"
        statusIcon.fontColor = GameColors.correctGreen
    }

    /// Landed wrong: register once, keep number/position/size, show ONLY
    /// a cross inside the block. No overlays, no shaking, no movement.
    func resolveWrong() {
        guard status == .active else { return }
        status = .wrongResolved
        hasBeenTriggered = true
        shape.fillColor = GameColors.disabledFill
        shape.strokeColor = GameColors.disabledStroke
        label.fontColor = .white
        label.alpha = 0.6
        statusIcon.text = "✕"
        statusIcon.fontColor = GameColors.wrongRed
    }

    /// Superseded by a new question (never triggered by the player):
    /// neutral look, number stays faintly visible, no icon.
    func markSuperseded(theme: AnimalCharacter) {
        guard status == .active else { return }
        status = .neutralResolved
        styleAsNeutral(theme: theme)
        label.fontColor = theme.skDeep
        label.run(.fadeAlpha(to: 0.35, duration: 0.3))
    }
}

// MARK: - Game scene

final class GameScene: SKScene {
    private let state: GameState
    private var theme = CharacterCatalog.character(id: "fox")

    // Player
    private var player = SKNode()
    private var playerSprite = SKLabelNode(fontNamed: "AvenirNext-Bold")
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
    private let bounceVelocity: CGFloat = 980
    private let playerHalfHeight: CGFloat = 20
    private let playerHalfWidth: CGFloat = 26
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
    // factor (~202 pt) every band gap incl. jitter (≤ 150 + 24 = 174 pt)
    // stays climbable. Placement margin keeps visible air between blocks
    // (based on real block size + landing space; configurable).
    private var platforms: [GamePlatform] = []
    private var nextSpawnY: CGFloat = 0
    private let minBandGap: CGFloat = 100
    private let maxBandGap: CGFloat = 150
    private let bandJitter: CGFloat = 12
    private let jumpSafetyFactor: CGFloat = 0.8
    private let placementMargin: CGFloat = 22   // visible air around every block

    // Spawn zone: new blocks are only ever created ABOVE the visible
    // viewport. The margin covers full block height (26), the highest
    // vertical speed (springboard launch, 1250 pt/s) over a few frames
    // of render latency, plus animation headroom.
    private let spawnMargin: CGFloat = 80
    // Forward buffer: bands are prepared several rows ahead so fast
    // climbs never catch up with the generator.
    private let spawnAheadBuffer: CGFloat = 600

    private var maxJumpHeight: CGFloat { bounceVelocity * bounceVelocity / (2 * -gravity) }
    private var helperEnabled = false
    private var totalClimb: CGFloat = 0

    /// 2 wrong blocks at the start (3 answer blocks total), more as the
    /// player climbs — never more than the question can supply.
    private var wrongAnswerCount: Int {
        min(2 + Int(totalClimb / 2500), 4)
    }

    // Deferred answer refresh — the next set only activates after the
    // confirmation, never in the landing frame.
    private var answerRefreshAt: TimeInterval?
    private var lastReachabilityCheck: TimeInterval = 0

    // Permanent bottom springboard: separate platform type, own height,
    // independent of the answer generator.
    private var springboard = SKShapeNode()
    private let springboardY: CGFloat = 46
    private let springboardVelocity: CGFloat = 1250

    // Loop
    private var lastUpdateTime: TimeInterval = 0
    private var started = false

    init(state: GameState) {
        self.state = state
        super.init(size: .zero)
        scaleMode = .resizeFill
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        startIfNeeded()
        startMotionUpdates()
    }

    override func willMove(from view: SKView) {
        stopMotionUpdates()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        startIfNeeded()
    }

    private func startIfNeeded() {
        guard !started, size.width > 50, size.height > 50 else { return }
        started = true
        setupSpringboard()
        setupPlayer()
        layoutNewGame()
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

        playerSprite = SKLabelNode(fontNamed: "AvenirNext-Bold")
        playerSprite.fontSize = 40
        playerSprite.verticalAlignmentMode = .center
        player.addChild(playerSprite)

        springNode = makeSpring()
        springNode.position = CGPoint(x: 0, y: -18)
        player.addChild(springNode)

        player.zPosition = 10
        addChild(player)
    }

    /// Drawn coil spring under the character.
    private func makeSpring() -> SKShapeNode {
        let path = CGMutablePath()
        let coilWidth: CGFloat = 16
        let coilHeight: CGFloat = 16
        let segments = 5
        path.move(to: .zero)
        for i in 1...segments {
            let x: CGFloat = (i == segments) ? 0 : (i.isMultiple(of: 2) ? -coilWidth / 2 : coilWidth / 2)
            let y = -coilHeight * CGFloat(i) / CGFloat(segments)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        let node = SKShapeNode(path: path)
        node.lineWidth = 2.5
        node.lineCap = .round
        node.lineJoin = .round
        return node
    }

    /// Places the player and an initial sparse set of platforms.
    func layoutNewGame() {
        guard started else { return }
        for platform in platforms { platform.removeFromParent() }
        platforms.removeAll()

        helperEnabled = GameSettings.answerHelperEnabled
        theme = CharacterCatalog.current(isPremium: GameSettings.premiumUnlockedCache)
        backgroundColor = theme.skSky
        playerSprite.text = theme.emoji
        springNode.strokeColor = theme.skDeep
        springboard.fillColor = theme.skPrimary
        springboard.strokeColor = theme.skDeep
        springboard.lineWidth = 2

        player.position = CGPoint(x: size.width / 2, y: 160)
        player.zRotation = 0
        velocityY = bounceVelocity
        velocityX = 0
        targetX = nil
        squashTimer = 0
        totalClimb = 0
        lastUpdateTime = 0
        answerRefreshAt = nil
        lastReachabilityCheck = 0

        // A guaranteed neutral platform right below the player.
        addNeutralPlatform(at: CGPoint(x: size.width / 2, y: 110))

        nextSpawnY = 240
        spawnPlatformsIfNeeded()
        buildAnswerSet() // validated before the first frame is playable
    }

    /// Restart after game over.
    func resetGame() {
        state.reset()
        layoutNewGame()
    }

    // MARK: Geometry & placement validation

    private func wrapDx(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        let d = abs(a - b)
        return min(d, size.width - d)
    }

    private func blockRect(at center: CGPoint) -> CGRect {
        CGRect(x: center.x - GamePlatform.platformSize.width / 2,
               y: center.y - GamePlatform.platformSize.height / 2,
               width: GamePlatform.platformSize.width,
               height: GamePlatform.platformSize.height)
    }

    /// Full-bounds AABB check against every existing block (expanded by
    /// the placement margin) and any already-planned positions.
    private func isFreePosition(_ center: CGPoint, planned: [CGPoint] = []) -> Bool {
        let candidate = blockRect(at: center)
        for platform in platforms {
            let expanded = blockRect(at: platform.position)
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
        return maxHorizontalSpeed * time * 0.7 + GamePlatform.platformSize.width / 2
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
        return dx < 90 && below > -40 && below < 200
    }

    // MARK: Answer set generation (fixed order, atomic activation)

    /// Fixed order: question → correct value → place correct block within
    /// safe distance → validate a route WITHOUT wrong blocks → place wrong
    /// blocks outside the route corridor → overlap/margins/reachability
    /// already guaranteed per placement → activate everything at once.
    private func buildAnswerSet() {
        // The old set is superseded: values, positions and sizes stay
        // exactly as they are; only their answer function is switched off.
        for platform in platforms where platform.isActiveAnswer {
            platform.markSuperseded(theme: theme)
        }

        let correctValue = state.correctAnswer

        for _ in 0..<3 {
            guard let correctPos = findCorrectPosition(), routeExists(toPosition: correctPos) else { continue }

            var planned: [CGPoint] = [correctPos]
            var wrongs: [(String, CGPoint)] = []
            for value in state.question.distractors.shuffled().prefix(wrongAnswerCount) {
                if let pos = findWrongPosition(correct: correctPos, planned: planned) {
                    planned.append(pos)
                    wrongs.append((value, pos))
                }
                // No safe spot for this wrong block → simply fewer wrong
                // blocks. That is always a valid layout.
            }
            activateAnswerSet(correct: (correctValue, correctPos), wrongs: wrongs)
            return
        }

        // Guaranteed minimal fallback: only the correct block, on a spot
        // that is freed up if necessary. Never an invalid layout.
        let pos = guaranteedCorrectPosition()
        activateAnswerSet(correct: (correctValue, pos), wrongs: [])
    }

    /// Spawn zone for answer blocks: fully ABOVE the visible viewport
    /// (bottom edge of a block clears viewportTop + spawnMargin), so new
    /// blocks only come into view through natural player movement.
    private func answerWindowYRange() -> ClosedRange<CGFloat> {
        let lower = size.height + spawnMargin + GamePlatform.platformSize.height / 2
        return lower...(lower + 260)
    }

    private func findCorrectPosition() -> CGPoint? {
        let yRange = answerWindowYRange()
        for _ in 0..<20 {
            let candidate = CGPoint(x: .random(in: 48...(size.width - 48)),
                                    y: .random(in: yRange))
            if isFreePosition(candidate) { return candidate }
        }
        return nil
    }

    private func findWrongPosition(correct: CGPoint, planned: [CGPoint]) -> CGPoint? {
        let yRange = answerWindowYRange()
        for _ in 0..<20 {
            let candidate = CGPoint(x: .random(in: 48...(size.width - 48)),
                                    y: .random(in: yRange))
            guard !blocksApproach(toCorrect: correct, candidate: candidate) else { continue }
            if isFreePosition(candidate, planned: planned) { return candidate }
        }
        return nil
    }

    /// Grid-scan for a free spot; as a last resort a non-answer block in
    /// the window is removed to make room. Always returns a valid position.
    private func guaranteedCorrectPosition() -> CGPoint {
        let yRange = answerWindowYRange()
        var y = yRange.lowerBound
        while y <= yRange.upperBound {
            var x: CGFloat = 60
            while x <= size.width - 60 {
                let candidate = CGPoint(x: x, y: y)
                if isFreePosition(candidate) { return candidate }
                x += 90
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
            let bottom = position.y - GamePlatform.platformSize.height / 2
            if bottom < size.height + spawnMargin - 1 {
                assertionFailure("Spawn: answer block created inside the visible spawn margin at \(position)")
            }
        }
#endif
        let correctBlock = GamePlatform(role: .answer, value: correct.0)
        correctBlock.position = correct.1
        correctBlock.styleAsActiveAnswer(theme: theme, isCorrect: true, helperEnabled: helperEnabled)
        addChild(correctBlock)
        platforms.append(correctBlock)

        for (value, position) in wrongs {
            let block = GamePlatform(role: .answer, value: value)
            block.position = position
            block.styleAsActiveAnswer(theme: theme, isCorrect: false, helperEnabled: helperEnabled)
            addChild(block)
            platforms.append(block)
        }
        debugValidateLayout()
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
        if let pos = findCorrectPosition(), routeExists(toPosition: pos) {
            activateAnswerSet(correct: (state.correctAnswer, pos), wrongs: [])
        } else {
            activateAnswerSet(correct: (state.correctAnswer, guaranteedCorrectPosition()), wrongs: [])
        }
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
        for (i, a) in platforms.enumerated() {
            for b in platforms[(i + 1)...] {
                let rectA = blockRect(at: a.position)
                let rectB = blockRect(at: b.position)
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
            assertionFailure("Layout: no wrong-answer-free route to the correct block")
        }
#endif
    }

    // MARK: Neutral platform spawning (while climbing)

    private func addNeutralPlatform(at position: CGPoint) {
        let platform = GamePlatform(role: .neutralPlatform)
        platform.position = position
        platform.styleAsNeutral(theme: theme)
        addChild(platform)
        platforms.append(platform)
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
        let count = CGFloat.random(in: 0...1) < 0.25 ? 2 : 1
        for _ in 0..<count {
            for _ in 0..<12 {
                let candidate = CGPoint(x: .random(in: 48...(size.width - 48)),
                                        y: y + CGFloat.random(in: -bandJitter...bandJitter))
                if isFreePosition(candidate) {
                    addNeutralPlatform(at: candidate)
                    break
                }
            }
        }
    }

    // MARK: Game loop

    override func update(_ currentTime: TimeInterval) {
        guard started, !state.isGameOver else { return }
        if lastUpdateTime == 0 { lastUpdateTime = currentTime }
        let dt = CGFloat(min(1.0 / 30.0, currentTime - lastUpdateTime))
        lastUpdateTime = currentTime

        updateHorizontal(dt: dt)

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
        if answerRefreshAt == nil, currentTime - lastReachabilityCheck > 0.75 {
            lastReachabilityCheck = currentTime
            ensureCorrectReachable()
        }

        updatePlayerAppearance(dt: dt)
        scrollIfNeeded()
        spawnPlatformsIfNeeded()
        cullPlatforms()
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
        let halfWidth = GamePlatform.platformSize.width / 2
        let halfHeight = GamePlatform.platformSize.height / 2

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
                    landedCorrect(on: platform)
                } else if dx < halfWidth - 10 {
                    // Only a clear landing can count as a wrong answer;
                    // an edge graze is just a bounce.
                    landedWrong(on: platform)
                }
            }
            return
        }
    }

    /// Flow: register once → checkmark INSIDE the block → block stays an
    /// ordinary platform (number, position, size unchanged) → the NEXT
    /// set is built later, validated, and activated in one update.
    private func landedCorrect(on platform: GamePlatform) {
        platform.resolveCorrect(theme: theme)
        haptic(success: true)
        PlaytimeTracker.shared.registerInteraction()
        state.answeredCorrectly()
        answerRefreshAt = lastUpdateTime + 0.65
    }

    /// Register once → cross INSIDE the block → nothing else changes.
    private func landedWrong(on platform: GamePlatform) {
        platform.resolveWrong()
        haptic(success: false)
        PlaytimeTracker.shared.registerInteraction()
        state.answeredWrong()
    }

    // MARK: Feedback

    private func haptic(success: Bool) {
#if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(success ? .success : .error)
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
