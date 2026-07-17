//
//  GameScene.swift
//  Jumping Fox
//
//  Doodle Jump–style gameplay: sparse platforms with open air between
//  them. Most platforms are neutral; a few show answers. Landing on the
//  correct answer scores; falling below the screen ends the game.
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

// MARK: - Platform

final class GamePlatform: SKNode {
    enum Kind {
        case neutral
        case answer
    }

    static let neutralSize = CGSize(width: 64, height: 16)
    static let answerSize = CGSize(width: 78, height: 30)

    let kind: Kind
    let bodySize: CGSize
    private let shape: SKShapeNode
    private let label: SKLabelNode
    private(set) var answer: String = ""
    /// A wrong platform that was already chosen: acts neutral afterwards.
    private(set) var isAnswered = false

    /// An answer platform that can still be chosen.
    var isActiveAnswer: Bool { kind == .answer && !isAnswered }

    init(kind: Kind) {
        self.kind = kind
        self.bodySize = kind == .answer ? Self.answerSize : Self.neutralSize
        shape = SKShapeNode(rectOf: bodySize, cornerRadius: bodySize.height / 2)
        shape.lineWidth = 2

        label = SKLabelNode(fontNamed: "AvenirNext-Bold")
        label.fontSize = 18
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center

        super.init()
        addChild(shape)
        if kind == .answer {
            addChild(label)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setAnswer(_ value: String) {
        answer = value
        label.text = value
        // Longer answers ("3/4", "50%") get a slightly smaller font.
        label.fontSize = value.count >= 5 ? 13 : (value.count == 4 ? 15 : 18)
    }

    /// Themed look; green/red when the answer helper is enabled.
    func applyStyle(theme: AnimalCharacter, correctAnswer: String, helperEnabled: Bool) {
        switch kind {
        case .neutral:
            shape.fillColor = GameColors.neutralFill
            shape.strokeColor = theme.skPrimary
        case .answer:
            guard !isAnswered else { return }
            if helperEnabled {
                let isCorrect = answer == correctAnswer
                shape.fillColor = isCorrect ? GameColors.correctGreen : GameColors.wrongRed
                shape.strokeColor = shape.fillColor.withAlphaComponent(0.6)
                label.fontColor = .white
            } else {
                shape.fillColor = theme.skPrimary
                shape.strokeColor = theme.skDeep
                label.fontColor = .white
            }
        }
    }

    /// Wrong answer chosen: turn gray and act as a neutral platform.
    func markAnswered() {
        isAnswered = true
        shape.fillColor = GameColors.disabledFill
        shape.strokeColor = GameColors.disabledStroke
        label.fontColor = .white
        run(.fadeAlpha(to: 0.55, duration: 0.2))
    }

    func flashWrong() {
        shape.fillColor = GameColors.wrongRed
        run(.sequence([
            .moveBy(x: -5, y: 0, duration: 0.04),
            .moveBy(x: 10, y: 0, duration: 0.06),
            .moveBy(x: -5, y: 0, duration: 0.04)
        ]))
    }

    func flashCorrect() {
        shape.fillColor = GameColors.goldFlash
        label.fontColor = .white
        run(.sequence([
            .scale(to: 1.15, duration: 0.08),
            .scale(to: 1.0, duration: 0.12)
        ]))
    }

    /// Small wobble for a harmless edge graze.
    func grazeWobble() {
        run(.sequence([
            .scaleY(to: 0.85, duration: 0.06),
            .scaleY(to: 1.0, duration: 0.10)
        ]))
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
    private let superJumpVelocity: CGFloat = 2500
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

    // Platforms — sparse bands with open air between them.
    private var platforms: [GamePlatform] = []
    private var nextSpawnY: CGFloat = 0
    private let minBandGap: CGFloat = 105
    private let maxBandGap: CGFloat = 180
    private var forceCorrectNext = false
    private var helperEnabled = false
    private var totalClimb: CGFloat = 0

    /// At most 3 answer platforms at the start; more as the player climbs.
    private var maxAnswerPlatforms: Int {
        min(6, 3 + Int(totalClimb / 2500))
    }

    // Loop
    private var lastUpdateTime: TimeInterval = 0
    private var superJumping = false
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

        player.position = CGPoint(x: size.width / 2, y: 160)
        player.zRotation = 0
        velocityY = bounceVelocity
        velocityX = 0
        targetX = nil
        superJumping = false
        squashTimer = 0
        totalClimb = 0
        lastUpdateTime = 0

        // A guaranteed neutral platform right below the player for the first bounce.
        let start = GamePlatform(kind: .neutral)
        start.position = CGPoint(x: size.width / 2, y: 100)
        addChild(start)
        platforms.append(start)

        nextSpawnY = 240
        forceCorrectNext = true // the first question is always reachable
        spawnPlatformsIfNeeded()
        ensureCorrectAnswerAvailable()
        restyleAllPlatforms()
        updateSuperJumpAvailability()
    }

    /// Restart after game over.
    func resetGame() {
        state.reset()
        layoutNewGame()
    }

    // MARK: Super jump

    func superJump() {
        guard started, !state.isGameOver, !superJumping else { return }
        superJumping = true
        PlaytimeTracker.shared.registerInteraction()
        velocityY = superJumpVelocity
        springNode.run(.sequence([
            .scaleY(to: 1.6, duration: 0.10),
            .scaleY(to: 1.0, duration: 0.25)
        ]))
    }

    // MARK: Spawning

    private func spawnPlatformsIfNeeded() {
        while nextSpawnY < size.height + 250 {
            spawnBand(at: nextSpawnY)
            nextSpawnY += CGFloat.random(in: minBandGap...maxBandGap)
        }
    }

    /// One band = usually a single platform, sometimes two, with open air around it.
    private func spawnBand(at y: CGFloat) {
        let count = CGFloat.random(in: 0...1) < 0.25 ? 2 : 1
        var usedXs: [CGFloat] = []
        for _ in 0..<count {
            var x = CGFloat.random(in: 55...(size.width - 55))
            var attempts = 0
            while attempts < 10 && usedXs.contains(where: { abs($0 - x) < 130 }) {
                x = CGFloat.random(in: 55...(size.width - 55))
                attempts += 1
            }
            usedXs.append(x)
            spawnPlatform(at: CGPoint(x: x, y: y + CGFloat.random(in: -18...18)))
        }
    }

    private func spawnPlatform(at position: CGPoint) {
        let activeAnswers = platforms.filter(\.isActiveAnswer).count
        let makeAnswer = activeAnswers < maxAnswerPlatforms && CGFloat.random(in: 0...1) < 0.5
        let platform = GamePlatform(kind: makeAnswer ? .answer : .neutral)
        platform.position = position

        if makeAnswer {
            if forceCorrectNext || (!hasVisibleCorrectPlatform() && CGFloat.random(in: 0...1) < 0.6) {
                platform.setAnswer(state.correctAnswer)
                forceCorrectNext = false
            } else {
                platform.setAnswer(state.distractor(excluding: activeAnswerValues()))
            }
        }
        platform.applyStyle(theme: theme, correctAnswer: state.correctAnswer, helperEnabled: helperEnabled)
        addChild(platform)
        platforms.append(platform)
    }

    private func activeAnswerValues() -> Set<String> {
        var values = Set(platforms.filter(\.isActiveAnswer).map(\.answer))
        values.insert(state.correctAnswer)
        return values
    }

    // MARK: Answer management

    /// Give every active answer platform a fresh answer for the current question.
    private func relabelForNewQuestion() {
        var used: Set<String> = [state.correctAnswer]
        for platform in platforms where platform.isActiveAnswer {
            let value = state.distractor(excluding: used)
            used.insert(value)
            platform.setAnswer(value)
        }
        // Usually keep the correct answer reachable; occasionally it is not,
        // which is exactly when the super jump comes into play.
        let candidates = platforms.filter {
            $0.isActiveAnswer && $0.position.y > player.position.y + 40 && $0.position.y < size.height + 60
        }
        if let chosen = candidates.randomElement(), CGFloat.random(in: 0...1) < 0.85 {
            chosen.setAnswer(state.correctAnswer)
        }
        restyleAllPlatforms()
    }

    /// Make sure the correct answer exists somewhere reachable. If there is
    /// no active answer platform, convert a neutral one above the player.
    private func ensureCorrectAnswerAvailable() {
        guard !hasVisibleCorrectPlatform() else { return }
        let answerCandidates = platforms.filter {
            $0.isActiveAnswer && $0.position.y > player.position.y + 40 && $0.position.y < size.height + 200
        }
        if let chosen = answerCandidates.randomElement() {
            chosen.setAnswer(state.correctAnswer)
        } else if let neutral = platforms.filter({
            $0.kind == .neutral && $0.position.y > player.position.y + 60 && $0.position.y < size.height + 200
        }).randomElement() {
            let replacement = GamePlatform(kind: .answer)
            replacement.position = neutral.position
            replacement.setAnswer(state.correctAnswer)
            addChild(replacement)
            platforms.append(replacement)
            neutral.removeFromParent()
            platforms.removeAll { $0 === neutral }
        }
        restyleAllPlatforms()
    }

    private func restyleAllPlatforms() {
        for platform in platforms {
            platform.applyStyle(theme: theme, correctAnswer: state.correctAnswer, helperEnabled: helperEnabled)
        }
    }

    private func hasVisibleCorrectPlatform() -> Bool {
        platforms.contains {
            $0.isActiveAnswer
                && $0.answer == state.correctAnswer
                && $0.position.y > player.position.y - 30
                && $0.position.y < size.height + 250
        }
    }

    private func updateSuperJumpAvailability() {
        let available = started && !state.isGameOver && !superJumping && !hasVisibleCorrectPlatform()
        if state.superJumpAvailable != available {
            state.superJumpAvailable = available
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

        if superJumping && velocityY <= 0 {
            superJumping = false
            ensureCorrectAnswerAvailable()
        }

        if velocityY < 0 && !superJumping {
            checkLanding(previousBottom: previousBottom)
        }

        // Falling below the screen ends the game.
        if player.position.y < -60 {
            haptic(success: false)
            state.fell()
            return
        }

        updatePlayerAppearance(dt: dt)
        scrollIfNeeded()
        spawnPlatformsIfNeeded()
        cullPlatforms()
        updateSuperJumpAvailability()
    }

    /// Tilt-first steering with touch fallback, smoothed for easy control.
    private func updateHorizontal(dt: CGFloat) {
        var desired: CGFloat = 0
        if let targetX {
            desired = (targetX - player.position.x) * 9
        } else if let tilt = currentTilt, abs(tilt) >= tiltDeadZone {
            // Gentle response curve: precise near center, faster at strong tilt.
            let magnitude = CGFloat(pow(Double(abs(tilt)), 1.25)) * tiltSensitivity
            desired = tilt < 0 ? -magnitude : magnitude
            // Actively moving the device counts as interaction for playtime.
            if abs(tilt - lastReportedTilt) > 0.08 {
                lastReportedTilt = tilt
                PlaytimeTracker.shared.registerInteraction()
            }
        }
        desired = min(max(desired, -maxHorizontalSpeed), maxHorizontalSpeed)
        velocityX += (desired - velocityX) * min(1, dt * 9)
        player.position.x += velocityX * dt

        // Horizontal screen wrapping: leave one side, appear on the other.
        // Only triggers once the player is fully past the edge (half width),
        // velocity and all other state stay untouched. The if/else guarantees
        // at most one wrap per frame.
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

        // Face the direction of travel (animal emoji face left).
        if velocityX > 60 { facing = -1 } else if velocityX < -60 { facing = 1 }
        playerSprite.xScale = facing * currentScaleX
        playerSprite.yScale = currentScaleY

        // Lean into the movement.
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

        for platform in platforms {
            let top = platform.position.y + platform.bodySize.height / 2
            guard previousBottom >= top - 2, bottom <= top else { continue }
            let dx = abs(player.position.x - platform.position.x)
            let halfWidth = platform.bodySize.width / 2
            guard dx < halfWidth + 6 else { continue }

            velocityY = bounceVelocity
            squashTimer = 0.14
            bounceSpring()

            if platform.isActiveAnswer {
                if platform.answer == state.correctAnswer {
                    landedCorrect(on: platform)
                } else if dx < halfWidth - 10 {
                    // Only a clear landing can count as a wrong answer.
                    landedWrong(on: platform)
                } else {
                    platform.grazeWobble()
                }
            }
            return
        }
    }

    private func landedCorrect(on platform: GamePlatform) {
        platform.flashCorrect()
        showPlusOne(at: platform.position)
        haptic(success: true)
        PlaytimeTracker.shared.registerInteraction()
        state.answeredCorrectly()
        relabelForNewQuestion()
    }

    private func landedWrong(on platform: GamePlatform) {
        platform.flashWrong()
        platform.markAnswered()
        flashDamage()
        haptic(success: false)
        PlaytimeTracker.shared.registerInteraction()
        state.answeredWrong()
    }

    // MARK: Feedback effects

    private func showPlusOne(at position: CGPoint) {
        let plusOne = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        plusOne.text = "+1"
        plusOne.fontSize = 28
        plusOne.fontColor = theme.skDeep
        plusOne.position = CGPoint(x: position.x, y: position.y + 34)
        plusOne.zPosition = 20
        addChild(plusOne)
        plusOne.run(.sequence([
            .group([.moveBy(x: 0, y: 70, duration: 0.7), .fadeOut(withDuration: 0.7)]),
            .removeFromParent()
        ]))

        let sparkle = SKLabelNode(fontNamed: "AvenirNext-Bold")
        sparkle.text = "✨"
        sparkle.fontSize = 24
        sparkle.position = CGPoint(x: position.x + 30, y: position.y + 20)
        sparkle.zPosition = 20
        sparkle.setScale(0.1)
        addChild(sparkle)
        sparkle.run(.sequence([
            .group([.scale(to: 1.2, duration: 0.25), .fadeOut(withDuration: 0.45)]),
            .removeFromParent()
        ]))
    }

    /// Brief red vignette when a life is lost.
    private func flashDamage() {
        let overlay = SKSpriteNode(color: GameColors.wrongRed, size: size)
        overlay.position = CGPoint(x: size.width / 2, y: size.height / 2)
        overlay.zPosition = 50
        overlay.alpha = 0
        addChild(overlay)
        overlay.run(.sequence([
            .fadeAlpha(to: 0.28, duration: 0.08),
            .fadeOut(withDuration: 0.30),
            .removeFromParent()
        ]))
    }

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
