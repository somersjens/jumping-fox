#if TRAILER_EXPORT
import SwiftUI
import SpriteKit
import UIKit
import Combine

/// Shared trailer chrome metrics so SpriteKit's springboard and SwiftUI's
/// equation badge stay locked to the same vertical band.
enum TrailerChrome {
    static let phoneSpringboardY: CGFloat = 118
    static let padSpringboardY: CGFloat = 200
    static let phoneSpringboardHeight: CGFloat = 14
    static let padSpringboardHeight: CGFloat = 18
    static let equationHeight: CGFloat = 58
    /// Equal air above and below the sum inside the band between the screen
    /// (or master crop) bottom and the springboard.
    static let bandSeam: CGFloat = 12

    static func springboardY(isPad: Bool) -> CGFloat {
        isPad ? padSpringboardY : phoneSpringboardY
    }

    static func springboardHeight(isPad: Bool) -> CGFloat {
        isPad ? padSpringboardHeight : phoneSpringboardHeight
    }

    static func equationBottomPadding(isPad: Bool, bottomCrop: CGFloat) -> CGFloat {
        let boardY = springboardY(isPad: isPad)
        let boardHalf = springboardHeight(isPad: isPad) / 2
        let bandBottom = bottomCrop + bandSeam
        let bandTop = boardY - boardHalf - bandSeam
        let band = max(equationHeight, bandTop - bandBottom)
        return bandBottom + (band - equationHeight) / 2
    }
}

@MainActor
final class PromoTrailerRecorder: ObservableObject {
    static let shared = PromoTrailerRecorder()

    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var themeID = "fox"

    private var startedAt: TimeInterval?
    private var timer: AnyCancellable?
    private var events: [(String, TimeInterval)] = []

    private var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AppStoreTeaser", isDirectory: true)
    }

    private func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    func prepare() {
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        try? Data("ready\n".utf8).write(to: url("playback-ready"), options: .atomic)
        timer?.cancel()
        timer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let startedAt = self.startedAt else { return }
                self.elapsed = ProcessInfo.processInfo.systemUptime - startedAt
            }
    }

    func waitForStart(_ action: @escaping @MainActor () -> Void) {
        if FileManager.default.fileExists(atPath: url("start").path) {
            start(action)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.waitForStart(action)
        }
    }

    private func start(_ action: @escaping @MainActor () -> Void) {
        guard startedAt == nil else { return }
        startedAt = ProcessInfo.processInfo.systemUptime
        elapsed = 0
        events.removeAll()
        event("start")
        action()
    }

    func event(_ name: String) {
        guard let startedAt else { return }
        let time = ProcessInfo.processInfo.systemUptime - startedAt
        events.append((name, time))
        if name.hasPrefix("character_") {
            themeID = String(name.dropFirst("character_".count))
        }
        persistEvents()
    }

    func finish(eventName: String = "end_card_settled") {
        event(eventName)
        persistEvents()
        try? Data("complete\n".utf8).write(to: url("playback-complete"), options: .atomic)
    }

    private func persistEvents() {
        let text = events.map { String(format: "%.3f\t%@", $0.1, $0.0) }
            .joined(separator: "\n") + "\n"
        try? Data(text.utf8).write(to: url("events.tsv"), options: .atomic)
    }
}

struct PromoTrailerView: View {
    @StateObject private var state: GameState
    @State private var scene: GameScene
    @ObservedObject private var recorder = PromoTrailerRecorder.shared
    @State private var endCardVisible = false
    @State private var iconSettled = false

    init() {
        let level = LevelCatalog.byCategory[.addition]![8]
        let questions = [
            Question(prompt: "9 + 6 = ?", correctAnswer: "15",
                     distractors: ["20"], isRandomPractice: false),
            Question(prompt: "7 × 8 = ?", correctAnswer: "56",
                     distractors: ["52", "63", "67"], isRandomPractice: false),
            Question(prompt: "8 + 8 = ?", correctAnswer: "16",
                     distractors: ["14"], isRandomPractice: false)
        ]
        let state = GameState(trailerLevel: level, questions: questions,
                              startingScore: 25, previousHighScore: 29)
        _state = StateObject(wrappedValue: state)
        _scene = State(initialValue: GameScene(state: state, trailerMode: true))
    }

    private var theme: AnimalCharacter {
        CharacterCatalog.character(id: recorder.themeID)
    }

    var body: some View {
        GeometryReader { proxy in
            // App Store masters centre-crop the simulator framebuffer. Place the
            // HUD just inside that crop with the same edge padding as GameView,
            // so pause / score / hearts read as edge-distributed — not clustered
            // in the middle of the wider capture frame.
            let phoneMasterAspect: CGFloat = 886 / 1920
            let tabletMasterAspect: CGFloat = 1200 / 1600
            let sourceAspect = proxy.size.width / max(proxy.size.height, 1)
            let phoneCropInset: CGFloat = {
                guard UIDevice.current.userInterfaceIdiom == .phone,
                      sourceAspect > phoneMasterAspect + 0.01 else { return 0 }
                let visibleWidth = proxy.size.height * phoneMasterAspect
                let cropEachSide = max(0, (proxy.size.width - visibleWidth) / 2)
                // 12pt inside the cropped edge ≈ GameView's 16pt after scale-up.
                return max(0, cropEachSide + 12 - GameHUDMetrics.horizontalPadding)
            }()
            let tabletCropTopInset: CGFloat = {
                guard UIDevice.current.userInterfaceIdiom == .pad,
                      sourceAspect < tabletMasterAspect - 0.01 else { return 0 }
                let visibleHeight = proxy.size.width / tabletMasterAspect
                let cropEachVertical = max(0, (proxy.size.height - visibleHeight) / 2)
                return max(0, cropEachVertical + 10)
            }()
            // Centre the sum in the band between the master-visible bottom and
            // the springboard (shared metrics with GameScene.TrailerChrome).
            let isPad = UIDevice.current.userInterfaceIdiom == .pad
            let bottomCrop: CGFloat = {
                guard isPad, sourceAspect < tabletMasterAspect - 0.01 else { return 0 }
                let visibleHeight = proxy.size.width / tabletMasterAspect
                return max(0, (proxy.size.height - visibleHeight) / 2)
            }()
            let equationBottomPadding = TrailerChrome.equationBottomPadding(
                isPad: isPad, bottomCrop: bottomCrop
            )
            ZStack {
                theme.skyColor.ignoresSafeArea()
                SpriteView(scene: scene,
                           options: [.shouldCullNonVisibleNodes, .ignoresSiblingOrder])
                    .background(theme.skyColor)
                    .ignoresSafeArea()
                    .blur(radius: endCardVisible ? 9 : 0)
                    .animation(.easeInOut(duration: 0.9), value: endCardVisible)

                VStack(spacing: 0) {
                    gameTopBar(extraHorizontalInset: phoneCropInset)
                        .padding(.top, tabletCropTopInset)
                    Spacer()
                    gameEquationBadge
                        .padding(.bottom, equationBottomPadding)
                }
                .ignoresSafeArea()
                .opacity(endCardVisible ? 0 : 1)
                .animation(.easeOut(duration: 0.45), value: endCardVisible)

                if endCardVisible {
                    Color.white.opacity(0.08).ignoresSafeArea()
                    appIcon(size: min(proxy.size.width * 0.58,
                                      proxy.size.height * 0.29))
                }
            }
            .ignoresSafeArea()
        }
        .onAppear {
            scene.isFrozen = true
            PromoTrailerRecorder.shared.prepare()
            AppAudio.shared.prepare()
            PromoTrailerRecorder.shared.waitForStart {
                scene.isFrozen = false
                AppAudio.shared.setGameplayActive(true, questionText: nil)
            }
        }
        .onChange(of: state.isGameOver) { over in
            guard over else { return }
            AppAudio.shared.setGameplayActive(false, questionText: nil)
            scene.fadeTrailerCaptionForEndCard()
            iconSettled = false
            endCardVisible = true
            // Insert the icon already rotated, then settle it upright on the
            // next frame so the twist is visible rather than skipped.
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.92, dampingFraction: 0.78)) {
                    iconSettled = true
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
                PromoTrailerRecorder.shared.finish()
            }
        }
        .preferredColorScheme(.light)
        .persistentSystemOverlays(.hidden)
        .statusBarHidden(true)
    }

    /// Matches the actual GameView HUD: pause at the leading edge, trophy
    /// score centred, and the real three-heart life row at the trailing edge.
    /// Equal-width side columns keep the score centred while pause/hearts sit
    /// on the cropped master edges (via `extraHorizontalInset`).
    private func gameTopBar(extraHorizontalInset: CGFloat) -> some View {
        let hudScale: CGFloat = UIDevice.current.userInterfaceIdiom == .phone ? 0.82 : 1
        let assetSize = GameHUDMetrics.assetSize * hudScale
        let pauseSize = GameHUDMetrics.pauseAssetSize * hudScale
        let scoreSize = GameHUDMetrics.scoreFontSize * hudScale
        let heartSpacing = GameHUDMetrics.heartSpacing * hudScale
        return HStack(spacing: 0) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: pauseSize, weight: .regular))
                .foregroundStyle(theme.deepColor)
                .frame(width: pauseSize, height: pauseSize)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Text(verbatim: "\(state.score)")
                    .font(.system(size: scoreSize,
                                  weight: .heavy, design: .rounded))
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.25), value: state.score)
                Image(systemName: "trophy.fill")
                    .font(.system(size: assetSize, weight: .regular))
                    .frame(width: assetSize, height: assetSize)
            }
            .fixedSize()

            HStack(spacing: heartSpacing) {
                ForEach(0..<3, id: \.self) { index in
                    trailerHeart(fill: min(2, max(0, (state.livesHalves ?? 0) - index * 2)))
                        .frame(width: assetSize, height: assetSize)
                }
            }
            .font(.system(size: assetSize, weight: .regular))
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .foregroundStyle(theme.deepColor)
        .padding(.horizontal, GameHUDMetrics.horizontalPadding + extraHorizontalInset)
        .padding(.top, 8)
    }

    private func trailerHeart(fill: Int) -> some View {
        ZStack {
            Image(systemName: "heart.fill")
                .foregroundStyle(theme.deepColor.opacity(0.28))
            if fill == 2 {
                Image(systemName: "heart.fill")
                    .foregroundStyle(theme.deepColor)
            } else if fill == 1 {
                Image(systemName: "heart.fill")
                    .foregroundStyle(theme.deepColor)
                    .mask(alignment: .leading) {
                        GeometryReader { geometry in
                            Rectangle().frame(width: geometry.size.width / 2)
                        }
                    }
            }
        }
    }

    /// Uses the same typography, gradient, corner geometry and bottom lane as
    /// the real game, keeping the sum directly beneath the springboard.
    private var gameEquationBadge: some View {
        Text(verbatim: state.questionText)
            .font(.system(size: 38, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .fixedSize()
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(
                LinearGradient(colors: [theme.color, theme.deepColor],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 20)
            )
            .shadow(color: theme.deepColor.opacity(0.35), radius: 8, y: 4)
            .padding(.horizontal, 12)
            .environment(\.layoutDirection, .leftToRight)
            .contentTransition(.numericText())
            .animation(.snappy(duration: 0.28), value: state.question.prompt)
    }

    private func appIcon(size: CGFloat) -> some View {
        Group {
            if let image = UIImage(named: "icon_for_trailer") ?? primaryAppIcon() {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225,
                                    style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 24, y: 12)
        .rotationEffect(.degrees(iconSettled ? 0 : -16))
        .scaleEffect((iconSettled ? 1 : 0.82)
                     * (iconSettled
                        ? 1 + sin(recorder.elapsed * .pi * 0.7) * 0.006
                        : 1))
        .opacity(iconSettled ? 1 : 0.88)
    }

    private func primaryAppIcon() -> UIImage? {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String],
              let name = files.last else { return nil }
        return UIImage(named: name)
    }
}
#endif
