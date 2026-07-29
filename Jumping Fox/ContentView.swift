//
//  ContentView.swift
//  Jumping Fox
//
//  Home screen: playtime progress, cyclic category selector with
//  arrow navigation (plus optional swipe), and redesigned level
//  cards with a big central number.
//

import SwiftUI
import Combine
import StoreKit
#if canImport(UIKit)
import UIKit
#endif

struct LevelSelection: Identifiable {
    let level: LevelConfig
    var id: String { level.id }
}

/// The brief return-to-menu celebration after a level earns more trophies.
/// Keeping the before-values makes the level, category and total counters all
/// visibly grow from the score the player just had.
private struct ScoreCelebration: Identifiable {
    let levelID: String
    let levelStart: Int
    let maximumCountStart: Int
    let categoryStart: Int
    let totalStart: Int
    /// Captured once from the before/after values. Views use this instead of
    /// re-reading a cache that may be reconciling while the menu appears.
    let scoreDidIncrease: Bool
    let id = UUID()
    /// When the celebration actually becomes visible on the menu. This is
    /// re-stamped the moment it is installed, not when it was constructed: the
    /// tutorial return holds the celebration back until its score hint has been
    /// read, and a stale timestamp made every time-driven view (the count-up and
    /// the return outline) compute a huge elapsed time and skip straight to the
    /// finished state — no count from old to new, no outline.
    var startedAt = Date()
}

/// Read-once progress used by the home menu. ProgressStore intentionally
/// reconciles UserDefaults and iCloud on a read, which is valuable at refresh
/// boundaries but far too expensive to repeat for every card during every
/// category change.
private struct HomeLevelProgress: Codable {
    var normalBest = 0
    var helperBest = 0
    var normalMaximumCount = 0
    var helperMaximumCount = 0
    var pausedNormal = 0
    var pausedIncludingHelper = 0
    var isPausedInCurrentLifeMode = false
}

private struct HomeProgressSnapshot: Codable {
    private static let cacheKey = "menu.homeProgressSnapshot.v1"

    var levels: [String: HomeLevelProgress] = [:]

    func value(for levelID: String) -> HomeLevelProgress {
        levels[levelID] ?? HomeLevelProgress()
    }

    /// The last fully rendered menu state is available synchronously on a cold
    /// launch. Persistent stores/cloud can then reconcile behind this state
    /// instead of briefly presenting every level as zero.
    static func loadCached() -> HomeProgressSnapshot {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let snapshot = try? JSONDecoder().decode(HomeProgressSnapshot.self, from: data) {
            return snapshot
        }

        // Migration/fallback for the first launch of the version that
        // introduced the menu snapshot. Read only local values: this is still
        // cheap enough to finish before the first frame and avoids a one-time
        // all-zero menu for existing players.
        let lifeModeRaw = UserDefaults.standard.string(forKey: GameSettings.lifeModeKey)
        let lifeMode = LifeMode(rawValue: lifeModeRaw ?? "") ?? .three
        let variants = LevelCatalog.byCategory.values
            .flatMap { $0 }
            .flatMap(\.allModeVariants)
        var snapshot = HomeProgressSnapshot()

        for level in variants where snapshot.levels[level.id] == nil {
            let id = level.id
            snapshot.levels[id] = HomeLevelProgress(
                normalBest: ProgressStore.locallyStoredBestScore(levelID: id),
                helperBest: ProgressStore.locallyStoredHelperOnlyBestScore(levelID: id),
                normalMaximumCount: ProgressStore.locallyStoredMaxCompletionCount(
                    levelID: id, helperEnabled: false
                ),
                helperMaximumCount: ProgressStore.locallyStoredMaxCompletionCount(
                    levelID: id, helperEnabled: true
                ),
                pausedNormal: PausedGameStore.shared.pausedScore(
                    forLevelID: id, includingHelper: false
                ),
                pausedIncludingHelper: PausedGameStore.shared.pausedScore(
                    forLevelID: id, includingHelper: true
                ),
                isPausedInCurrentLifeMode: PausedGameStore.shared.hasPausedSession(
                    for: level, mode: lifeMode
                )
            )
        }
        snapshot.persist()
        return snapshot
    }

    func persist() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
    }
}

/// Combines the 2D turn and its small circular flight path into one animatable
/// render transform. Unlike `sin/cos` calculated in a View body, this receives
/// every interpolated animation frame without rebuilding the menu or cards.
private struct CharacterSaltoGeometryEffect: GeometryEffect {
    var angle: Double
    let radius: CGFloat

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let radians = angle * .pi / 180
        let orbitX = CGFloat(sin(radians)) * radius
        let orbitY = CGFloat(cos(radians) - 1) * radius
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        var transform = CGAffineTransform(
            translationX: center.x + orbitX,
            y: center.y + orbitY
        )
        transform = transform.rotated(by: CGFloat(radians))
        transform = transform.translatedBy(x: -center.x, y: -center.y)
        return ProjectionTransform(transform)
    }
}

/// Mutable sequencing state that deliberately does not publish view changes.
/// Queueing another salto must not invalidate and rebuild the entire home menu.
private final class CharacterJumpCoordinator: ObservableObject {
    @Published var offset: CGFloat = 0
    @Published var squash: CGFloat = 1
    @Published var rotation: Double = 0
    var isJumping = false
    var pendingFlips: [Bool] = []
}

/// The only view subscribed to the animated pose. Keeping that subscription
/// here prevents five pose phases per jump from invalidating every level card,
/// score and menu control in ContentView.
private struct HomeCharacterArtwork: View {
    let character: AnimalCharacter
    let box: CGFloat
    @ObservedObject var jump: CharacterJumpCoordinator

    /// The lion's mane and the penguin's wide head fill more of their source
    /// canvases than the other home-screen characters. Compensate only here:
    /// the collection and gameplay deliberately keep their existing sizing.
    private var artworkScale: CGFloat {
        switch character.id {
        case "lion": 0.88
        case "penguin": 0.85
        default: 1
        }
    }

    var body: some View {
        character.artwork
            .resizable()
            .scaledToFill()
            .frame(width: box, height: box)
            .scaleEffect(artworkScale)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .scaleEffect(x: 1, y: jump.squash, anchor: .bottom)
            .modifier(CharacterSaltoGeometryEffect(
                angle: jump.rotation,
                radius: box * 0.105
            ))
            .offset(y: jump.offset)
    }
}

/// An eager, adaptive grid for the level menu. `LazyVGrid` discards cards
/// outside the viewport; when the options panel changes height, those cards
/// can otherwise appear to animate in from the bottom while scrolling.
/// The home screens intentionally keep the same visual hierarchy on iPhone
/// and iPad. On iPad, however, the controls and cards need room to breathe
/// rather than becoming a dense six-column grid.
enum AppLayout {
    static var isPad: Bool {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
#else
        false
#endif
    }
}

private struct AdaptiveLevelGrid: Layout {
    let spacing: CGFloat
    let minimumCardWidth: CGFloat
    let maximumColumns: Int
    let cardHeight: CGFloat

    init(spacing: CGFloat,
         minimumCardWidth: CGFloat = 104,
         maximumColumns: Int = .max,
         cardHeight: CGFloat = 96) {
        self.spacing = spacing
        self.minimumCardWidth = minimumCardWidth
        self.maximumColumns = maximumColumns
        self.cardHeight = cardHeight
    }

    private func metrics(for width: CGFloat, itemCount: Int) -> (columns: Int, cardWidth: CGFloat) {
        let possibleColumns = max(1, Int((width + spacing) / (minimumCardWidth + spacing)))
        let columns = min(max(1, itemCount), possibleColumns, maximumColumns)
        let cardWidth = (width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        return (columns, cardWidth)
    }

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: Subviews,
                      cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let fallbackColumns = min(subviews.count, maximumColumns)
        let fallbackWidth = minimumCardWidth * CGFloat(fallbackColumns)
            + spacing * CGFloat(fallbackColumns - 1)
        let width = proposal.width ?? fallbackWidth
        let columns = metrics(for: width, itemCount: subviews.count).columns
        let rows = Int(ceil(Double(subviews.count) / Double(columns)))
        return CGSize(width: width, height: CGFloat(rows) * cardHeight + CGFloat(rows - 1) * spacing)
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let grid = metrics(for: bounds.width, itemCount: subviews.count)
        for (index, subview) in subviews.enumerated() {
            let row = index / grid.columns
            let column = index % grid.columns
            let x = bounds.minX + CGFloat(column) * (grid.cardWidth + spacing)
            let y = bounds.minY + CGFloat(row) * (cardHeight + spacing)
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                          proposal: ProposedViewSize(width: grid.cardWidth, height: cardHeight))
        }
    }
}

/// The six topic filters. Each has a regular menu and an immediate-mix form.
enum MenuFilter: Int, CaseIterable, Identifiable {
    case addition, subtraction, tables, fractions, percentages, mixed

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .addition: return L("filter.addition")
        case .subtraction: return L("filter.subtraction")
        case .tables: return L("filter.tables")
        case .fractions: return L("filter.fractions")
        case .percentages: return L("filter.percentages")
        case .mixed: return L("filter.mixed")
        }
    }

    var icon: String {
        // Bare glyphs, not the `.circle.fill` variants: the surrounding button
        // already provides the circle, so the only solid is the selected one.
        switch self {
        case .addition: return "plus"
        case .subtraction: return "minus"
        case .tables: return "multiply"
        case .fractions: return "divide"
        case .percentages: return "percent"
        case .mixed: return "star.fill"
        }
    }

    var standard: ChallengeCategory {
        switch self {
        case .addition: return .addition
        case .subtraction: return .subtraction
        case .tables: return .tables
        case .fractions: return .fractions
        case .percentages: return .percentages
        // The Supermix filter picks its category from its own four-button
        // row instead (see `ContentView.supermixCategory`); this default is
        // never actually shown.
        case .mixed: return .superBasic
        }
    }

    func category(for mode: PracticeMode) -> ChallengeCategory { standard }

    /// One-line "what this topic practises" summary, shown in the tap-again
    /// info pop-out under the shared `info.filter.header` ("Types of problems").
    var infoBody: String {
        switch self {
        case .addition: return L("info.filter.addition")
        case .subtraction: return L("info.filter.subtraction")
        case .tables: return L("info.filter.tables")
        case .fractions: return L("info.filter.fractions")
        case .percentages: return L("info.filter.percentages")
        case .mixed: return L("info.filter.mixed")
        }
    }
}

// MARK: - Home screen

struct ContentView: View {
    @AppStorage(GameSettings.characterKey) private var characterID = "fox"
    @AppStorage(GameSettings.playerNameKey) private var playerName = ""
    @AppStorage(GameSettings.onboardingCompleteKey) private var onboardingComplete = false
    @AppStorage(GameSettings.lifeModeKey) private var lifeModeRaw = LifeMode.three.rawValue
    @AppStorage(GameSettings.answerHelperKey) private var answerHelper = false
    @AppStorage(GameSettings.capTrophiesKey) private var capsTrophiesAtThirty = true
    @AppStorage("ui.menuFilter") private var menuFilterRaw = MenuFilter.tables.rawValue
    @AppStorage("ui.menuMode") private var menuModeRaw = PracticeMode.order.rawValue
    @AppStorage("ui.supermixCategory") private var supermixCategoryRaw = ChallengeCategory.superBasic.rawValue
    @ObservedObject private var premium = PremiumStore.shared
    @ObservedObject private var progress = ProgressSync.shared
    // Re-renders code-resolved strings (menu names, options) on a language switch.
    @ObservedObject private var language = LanguageManager.shared
    @ObservedObject private var tutorial = TutorialProgress.shared
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: LevelSelection?
    @State private var showPremium = false
    @State private var premiumInitialCharacterID: String?
    @State private var celebratedCharacterUnlock: TrophyCharacterMilestone?
    @State private var isCharacterUnlockPreview = false
    @State private var pendingCharacterUnlocks: [TrophyCharacterMilestone] = []
    @State private var showGoalPicker = false
    @State private var showNameEditor = false
    @State private var nameDraft = ""
    @State private var refreshID = UUID()
    @State private var showsOptions = false
    @State private var expandedOptionInfo: String?
    @State private var lastOpenedLevelID: String?
    @State private var lastOpenedLevel: LevelConfig?
    @State private var openedLevelScore = 0
    @State private var openedLevelMaximumCount = 0
    @State private var openedCategoryTrophies = 0
    @State private var openedTotalTrophies = 0
    @State private var scoreCelebration: ScoreCelebration?
    @State private var highlightsHeaderTrophies = false
    @State private var showTutorialScoreHint = false
    @State private var scoreHintLevelID: String?
    // Runs when the score hint is dismissed, so the first-play return can wait
    // for the hint to be read before starting its celebration.
    @State private var afterScoreHint: (() -> Void)?
    @State private var suppressCharacterTap = false
    // A jump is a single, non-interruptible sequence. A selection made while
    // it is airborne is queued as a celebratory flip-jump after landing,
    // rather than fighting the current offset animation.
    @State private var characterJumpCoordinator = CharacterJumpCoordinator()
    @State private var homeProgress = HomeProgressSnapshot.loadCached()
    @State private var homeProgressGeneration = 0
    @State private var defersHomeProgressRefresh = false
    @State private var maximumCountPreview: Int?
    @State private var maximumCountPreviewLevelID: String?
    @State private var secondMaximumCountPreview: Int?
    @State private var secondMaximumCountPreviewLevelID: String?
    @State private var secondScorePreview: Int?
    @State private var secondScorePreviewLevelID: String?
    // Tap-again info pop-out: the little themed card that appears when the
    // already-selected topic (+, −, …) or order (Reeks/Hussel/Gemixt) is
    // tapped a second time. `levelFrames`/`controlAnchors` are collected in the
    // shared "home" coordinate space so the pop-out can anchor to the control
    // and a tap on a level card can both dismiss it and start that level.
    @State private var infoPopup: InfoPopup?
    @State private var levelFrames: [String: CGRect] = [:]
    @State private var controlAnchors: [String: CGRect] = [:]
    // Launch/land frames for the trophy that flies from a level card up to the
    // category header once that level earns more, plus the live flight itself.
    @State private var cardTrophyAnchors: [String: CGRect] = [:]
    @State private var homeViewportFrame: CGRect = .zero
    @State private var flyingTrophy: FlyingTrophy?
    // When the flying trophy merges into the header, the category and grand
    // totals start counting from this instant — decoupled from the card's own
    // earlier count-up so the numbers grow exactly as the reward arrives.
    @State private var headerTrophyArrival: Date?
    @State private var finishedCardCelebrations: Set<UUID> = []
    // Lets the trophy celebration scroll the header total back into view when a
    // higher level has scrolled it off the top of the menu.
    @State private var scrollProxy: ScrollViewProxy?
    // Authoritative first-max phase owned by the persistent home view. A level
    // card may be rebuilt while its score counts up; keeping this phase here
    // prevents that rebuild from cancelling the reveal or the subsequent flight.
    @State private var reachedMaximumCelebrationID: UUID?

    private var lifeMode: LifeMode { LifeMode(rawValue: lifeModeRaw) ?? .three }
    private var character: AnimalCharacter { CharacterCatalog.current(isPremium: premium.isPremium) }
    private var selectedFilter: MenuFilter { MenuFilter(rawValue: menuFilterRaw) ?? .tables }
    private var menuMode: PracticeMode { PracticeMode(rawValue: menuModeRaw) ?? .order }
    private var supermixCategory: ChallengeCategory {
        ChallengeCategory(rawValue: supermixCategoryRaw) ?? .superBasic
    }
    private var category: ChallengeCategory {
        selectedFilter == .mixed ? supermixCategory : selectedFilter.category(for: menuMode)
    }
    private var premiumSectionTitle: LocalizedStringKey {
        category == .tables ? "menu.premiumTables" : "menu.premium"
    }
    private var isPad: Bool { AppLayout.isPad }
    private var menuScale: CGFloat { isPad ? 1.64 : 1 }
    private var levelCardHeight: CGFloat { isPad ? 152 : 96 }
    /// iPad has enough horizontal room for more prominent topic controls;
    /// iPhone retains its established compact tap targets.
    private var filterButtonDiameter: CGFloat { isPad ? 82 : 44 }
    /// Keep the mode choices comfortably above the compact options control,
    /// without making the three-button row unnecessarily tall on iPad.
    private var modeButtonHeight: CGFloat { isPad ? 72 : 42 }
    // Keep the level cards visually grouped in columns, but leave enough
    // vertical air between rows on the much taller iPad cards.
    private var levelGridSpacing: CGFloat { isPad ? 24 : 12 }
    /// On iPad, give the menu's stacked control rows just enough separation
    /// to match their larger controls without turning the header into a list.
    private var menuCardSectionSpacing: CGFloat { isPad ? 24 : 14 }
    private var menuControlSpacing: CGFloat { isPad ? 22 : 11 }

    var body: some View {
        // Read the revision so an iCloud update redraws all score cards.
        let _ = progress.revision
        ZStack {
            GeometryReader { geo in
                Color.clear.preference(
                    key: HomeViewportFrameKey.self,
                    value: geo.frame(in: .named(Self.homeSpace))
                )
            }

            LinearGradient(
                colors: [character.skyColor, character.tintColor],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: isPad ? 26 : 18) {
                        menuCard.opacity(showTutorialScoreHint ? 0.30 : 1)
                            .id(Self.headerScrollID)
                        levelGrid
                    }
                    .padding(isPad ? 32 : 16)
                    .frame(maxWidth: isPad ? 900 : 720)
                    .frame(maxWidth: .infinity)
                    .id(refreshID)
                }
                .onAppear { scrollProxy = proxy }
            }

            if let popup = infoPopup {
                infoPopupOverlay(popup)
                    .transition(.opacity)
            }

            // The trophy that flies from a card up to the category header lives
            // here, above the scroll content and inside the "home" space, so its
            // reported source/destination frames line up one-to-one.
            if let flight = flyingTrophy {
                FlyingTrophyView(flight: flight)
            }
        }
        .coordinateSpace(name: Self.homeSpace)
        .onPreferenceChange(LevelFrameKey.self) { levelFrames = $0 }
        .onPreferenceChange(ControlAnchorKey.self) { controlAnchors = $0 }
        .onPreferenceChange(CardTrophyAnchorKey.self) { cardTrophyAnchors = $0 }
        .onPreferenceChange(HomeViewportFrameKey.self) { homeViewportFrame = $0 }
        .sheet(isPresented: $showPremium, onDismiss: {
            celebratedCharacterUnlock = nil
            premiumInitialCharacterID = nil
            isCharacterUnlockPreview = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if !presentPendingCharacterUnlockIfPossible() {
                    requestReviewAfterSettledReturn()
                }
            }
        }) {
            PremiumView(
                initialCharacterID: premiumInitialCharacterID,
                celebratedUnlock: celebratedCharacterUnlock,
                isUnlockPreview: isCharacterUnlockPreview
            )
                .premiumSheetPresentation()
        }
        .sheet(isPresented: $showNameEditor) {
            NameEditorSheet(theme: character, name: $nameDraft) {
                let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { playerName = trimmed }
            }
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.visible)
            .presentationBackground {
                LinearGradient(colors: [character.skyColor, character.tintColor],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .gameCover(item: $selection, onDismiss: {
            // Stop any in-flight all-level reconciliation from replacing the
            // menu snapshot while the return celebration is running.
            defersHomeProgressRefresh = true
            homeProgressGeneration += 1

            let shouldShowTutorialHint = tutorial.shouldShowScoreHint

            guard let levelID = lastOpenedLevelID, let level = lastOpenedLevel else {
                defersHomeProgressRefresh = false
                refreshHomeProgress()
                return
            }

            // Gameplay can only have changed this level. Reading and patching
            // that one entry avoids rebuilding every card as the cover leaves.
            let updatedProgress = readHomeProgress(for: level)
            let newScore = answerHelper
                ? max(updatedProgress.normalBest, updatedProgress.helperBest)
                : updatedProgress.normalBest
            let newMaximumCount = answerHelper
                ? updatedProgress.helperMaximumCount
                : updatedProgress.normalMaximumCount
            let scoreDidIncrease = newScore > openedLevelScore
            let earnedMore = scoreDidIncrease
                || newMaximumCount > openedLevelMaximumCount
            var updatedSnapshot = homeProgress
            updatedSnapshot.levels[levelID] = updatedProgress
            // Encode/write before the live-frame barrier, so persistence can
            // never steal time from the outline and score animations.
            updatedSnapshot.persist()

            let celebration = ScoreCelebration(levelID: levelID,
                                               levelStart: openedLevelScore,
                                               maximumCountStart: openedLevelMaximumCount,
                                               categoryStart: openedCategoryTrophies,
                                               totalStart: openedTotalTrophies,
                                               scoreDidIncrease: scoreDidIncrease)

            Task { @MainActor in
                // fullScreenCover can finish its dismissal using a snapshot of
                // the presenting view. Give the menu one real presentation
                // frame before changing the score or starting its animations.
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(24))
                guard selection == nil, lastOpenedLevelID == levelID else {
                    defersHomeProgressRefresh = false
                    refreshHomeProgress()
                    return
                }

                // First play: the score hint must introduce the number *before*
                // any of the return animation. Keep the old score on screen (do
                // not install the new snapshot yet) until the hint is read, then
                // run the whole celebration. Every later return skips this and
                // animates immediately, so nothing else is delayed.
                if shouldShowTutorialHint && earnedMore {
                    scheduleTutorialScoreHint(for: levelID, after: 0.05) {
                        installAndCelebrate(celebration: celebration,
                                            levelID: levelID,
                                            snapshot: updatedSnapshot,
                                            earnedMore: earnedMore,
                                            targetScore: newScore,
                                            showTutorialHintAfter: false)
                    }
                    return
                }

                installAndCelebrate(celebration: celebration,
                                    levelID: levelID,
                                    snapshot: updatedSnapshot,
                                    earnedMore: earnedMore,
                                    targetScore: newScore,
                                    showTutorialHintAfter: shouldShowTutorialHint)
            }
        })
        .onChange(of: selection?.id) { selectionID in
            guard let selectionID else { return }
            ReviewRequestCoordinator.shared.discardPendingReturn()
            // Starting another level ends any return celebration cleanly. Its
            // delayed callbacks are ID-guarded and therefore become no-ops.
            if scoreCelebration != nil {
                scoreCelebration = nil
                highlightsHeaderTrophies = false
                flyingTrophy = nil
                headerTrophyArrival = nil
                reachedMaximumCelebrationID = nil
                defersHomeProgressRefresh = false
            }
            lastOpenedLevelID = selectionID
            lastOpenedLevel = selection?.level
            openedLevelScore = displayedScore(forLevelID: selectionID)
            openedLevelMaximumCount = displayedMaximumCount(forLevelID: selectionID)
            openedCategoryTrophies = categoryTrophies
            openedTotalTrophies = totalTrophies
        }
        .task {
            premium.startInitialRefresh()
            refreshHomeProgress()
        }
        .onChange(of: progress.revision) { _ in
            refreshHomeProgress()
        }
        .onChange(of: lifeModeRaw) { _ in
            refreshHomeProgress()
        }
        .onAppear {
            // Preload players/voice off the main thread, then start the loop:
            // the background music plays app-wide, softly on the menus.
            AppAudio.shared.prepare()
            AppAudio.shared.startMusic()
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            AppAudio.shared.startMusic()
            requestReviewAfterSettledReturn()
        }
        .overlay {
            if showTutorialScoreHint {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.06).ignoresSafeArea()
                    Text("tutorial.scoreHint")
                        .font(isPad
                              ? .system(size: 28, weight: .heavy, design: .rounded)
                              : .headline.weight(.heavy))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(.horizontal, isPad ? 32 : 20)
                        .padding(.vertical, isPad ? 20 : 14)
                        .frame(maxWidth: isPad ? 620 : nil)
                        .background(character.deepColor.opacity(0.96), in: Capsule())
                        .overlay(
                            Capsule().stroke(
                                .white.opacity(0.9),
                                lineWidth: isPad ? 3 : 2
                            )
                        )
                        .shadow(
                            color: .black.opacity(0.28),
                            radius: isPad ? 13 : 8,
                            y: isPad ? 5 : 3
                        )
                        .padding(.horizontal, isPad ? 36 : 22)
                        // Match the iPhone placement proportionally to the
                        // menu's 1.64× iPad scale instead of pinning the larger
                        // prompt to the old 112-point phone offset.
                        .padding(.top, isPad ? 184 : 112)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    finishTutorialScoreHint()
                }
            }
        }
    }

    private var displayName: String { playerName.isEmpty ? "Jumping Fox" : playerName }
    /// The name as shown in the header. When it's a single long word we insert
    /// invisible soft hyphens so it can break across two lines with a "-";
    /// names with spaces just wrap at the space (no hyphen).
    private var wrappableName: String {
        displayName.contains(" ")
            ? displayName
            : displayName.map(String.init).joined(separator: "\u{00AD}")
    }

    /// A long press on the home character always restarts the welcome flow.
    /// Developer mode belongs to the character on the level start screen.
    private func restartOnboarding() {
#if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
#endif
        onboardingComplete = false
    }

    /// Makes the home character spring up out of its box and settle back.
    /// A category switch (+ → −) gets a big hop whose bottom reaches halfway up
    /// the box; a subcategory switch (Reeks → Hussel) gets a smaller quarter hop.
    private func triggerCharacterJump(big: Bool) {
        // Do not restart an in-flight animation: that was the source of the
        // visible hitch. Keep a small, bounded queue so rapid tapping can never
        // create an unbounded pile of animation closures.
        guard !characterJumpCoordinator.isJumping else {
            if characterJumpCoordinator.pendingFlips.count < 3 {
                characterJumpCoordinator.pendingFlips.append(big)
            }
            return
        }

        performCharacterJump(big: big, flips: false)
    }

    private func performCharacterJump(big: Bool, flips: Bool) {
        characterJumpCoordinator.isJumping = true

        let box: CGFloat = isPad ? 118 : 68
        // A queued salto is deliberately more airborne than an ordinary hop.
        let peak = box * (big ? 0.5 : 0.25) * (flips ? 1.34 : 1)
        let squash: CGFloat = big ? 0.70 : 0.80   // spring compressed before launch
        let stretch: CGFloat = big ? 1.12 : 1.07  // body elongated while rising
        let dip = box * 0.03                       // small crouch downwards
        let crouch = big ? 0.22 : 0.18
        let rise = big ? 0.18 : 0.14
        let ordinaryLandingSettle = big ? 0.72 : 0.60
        let flipHalfFlight = big ? 0.28 : 0.25
        let flipLandingSettle = 0.50

        // 1. Anticipation: the spring compresses and the character dips down.
        // A longer ease-in-out makes the wind-up read as a smooth crouch.
        withAnimation(.easeInOut(duration: crouch)) {
            characterJumpCoordinator.squash = squash
            characterJumpCoordinator.offset = dip
        }
        // 2. Launch: an ordinary jump keeps its established springy motion.
        // A salto uses two equal flight halves so the turn, apex and touchdown
        // stay synchronised as one movement.
        DispatchQueue.main.asyncAfter(deadline: .now() + crouch) {
            if flips {
                withAnimation(.easeOut(duration: flipHalfFlight)) {
                    characterJumpCoordinator.offset = -peak
                    characterJumpCoordinator.squash = 1.04
                }
                // Linear rotation is important here: 180° coincides with the
                // apex and 360° with touchdown.
                withAnimation(.linear(duration: flipHalfFlight * 2)) {
                    characterJumpCoordinator.rotation = 360
                }
            } else {
                withAnimation(.easeOut(duration: rise)) {
                    characterJumpCoordinator.offset = -peak
                    characterJumpCoordinator.squash = stretch
                }
            }
        }

        if flips {
            // Descend during the second half of the turn. The circular offset
            // also returns to zero at 360°, so every transform reaches the
            // landing point together.
            DispatchQueue.main.asyncAfter(deadline: .now() + crouch + flipHalfFlight) {
                withAnimation(.easeIn(duration: flipHalfFlight)) {
                    characterJumpCoordinator.offset = 0
                    characterJumpCoordinator.squash = 0.84
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + crouch + flipHalfFlight * 2) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.58)) {
                    characterJumpCoordinator.offset = 0
                    characterJumpCoordinator.squash = 1
                }
            }
            DispatchQueue.main.asyncAfter(
                deadline: .now() + crouch + flipHalfFlight * 2 + flipLandingSettle
            ) {
                completeCharacterLanding()
            }
        } else {
            // Ordinary landing: falls back with an under-damped spring, so the
            // scale briefly squashes on impact before settling to rest.
            DispatchQueue.main.asyncAfter(deadline: .now() + crouch + rise) {
                withAnimation(.spring(response: big ? 0.38 : 0.30, dampingFraction: 0.5)) {
                    characterJumpCoordinator.offset = 0
                    characterJumpCoordinator.squash = 1
                }
            }
            DispatchQueue.main.asyncAfter(
                deadline: .now() + crouch + rise + ordinaryLandingSettle
            ) {
                completeCharacterLanding()
            }
        }
    }

    /// Pins the character to its exact resting pose after the visual spring has
    /// fully settled, then holds that pose briefly. This small beat makes every
    /// landing readable before a queued salto starts winding up.
    private func completeCharacterLanding() {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            characterJumpCoordinator.offset = 0
            characterJumpCoordinator.squash = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            finishCharacterJump()
        }
    }

    /// Ends one fully settled jump and starts at most one queued successor.
    /// Keeping this hand-off serial means offset, scale and rotation animations
    /// can never overlap, even under very rapid tapping.
    private func finishCharacterJump() {
        characterJumpCoordinator.isJumping = false
        guard !characterJumpCoordinator.pendingFlips.isEmpty else { return }

        let flipIsBig = characterJumpCoordinator.pendingFlips.removeFirst()
        // 360° and 0° render identically; resetting without animation prevents
        // the angle from growing indefinitely between queued flips.
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            characterJumpCoordinator.rotation = 0
        }
        performCharacterJump(big: flipIsBig, flips: true)
    }

    // MARK: Combined top menu

    private var menuCard: some View {
        VStack(spacing: menuCardSectionSpacing) {
            // A little extra room keeps the iPad header actions from reading
            // as one dense cluster when the player name is short.
            HStack(alignment: .center, spacing: isPad ? 20 : 12) {
                Button {
                    // A long press may also end as a button tap; consume that
                    // trailing action instead of opening the premium sheet.
                    guard !suppressCharacterTap else {
                        suppressCharacterTap = false
                        return
                    }
                    AppAudio.shared.playMenuTap()
                    openCharacterCollection()
                } label: {
                    let box: CGFloat = isPad ? 118 : 68
                    ZStack {
                        // The fixed box: background sky plus its white outline.
                        // Neither moves or resizes; a little sky shows through
                        // while the character is airborne. The outline lives here
                        // (behind the character) so the character hops in front of
                        // it rather than being cut off by it.
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(LinearGradient(colors: [character.skyColor, character.tintColor],
                                                 startPoint: .top, endPoint: .bottom))
                            .overlay {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(.white.opacity(0.9), lineWidth: 2)
                            }
                        // Only the character hops. It is clipped to the box shape,
                        // squashed/stretched from its base (the spring), then
                        // offset up as a whole so it can rise clear of the top edge.
                        HomeCharacterArtwork(character: character,
                                             box: box,
                                             jump: characterJumpCoordinator)
                    }
                    .frame(width: box, height: box)
                    .shadow(color: character.deepColor.opacity(0.18), radius: 7, y: 3)
                }
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                // This is deliberately high priority: unlike the old pair of
                // independent tap gestures, a 2-second hold cannot be won by
                // the ordinary character-button tap.
                .highPriorityGesture(
                    LongPressGesture(minimumDuration: 2)
                        .onEnded { _ in
                            suppressCharacterTap = true
                            restartOnboarding()
                        }
                )
                .accessibilityLabel("menu.accessibility.character")
                .accessibilityHint("developerMode.accessibilityHint")

                VStack(alignment: .leading, spacing: 6) {
                    if tutorial.developerMode {
                        Text("developerMode.title")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(character.deepColor)
                    }
                    Button {
                        nameDraft = playerName
                        showNameEditor = true
                    } label: {
                        Text(wrappableName)
                            .font(.system(size: isPad ? 30 : 20, weight: .heavy, design: .rounded))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .minimumScaleFactor(0.6)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(displayName)
                    }
                    .buttonStyle(.plain)

                    Label {
                        // The trophy icon already says "trophies"; just the count.
                        let total = headerCount(start: scoreCelebration?.totalStart,
                                                current: totalTrophies)
                        TrophyCountText(from: total.from,
                                         to: total.to,
                                         celebrationStartedAt: total.at,
                                         suffix: answerHelper ? "*" : "",
                                         delay: 0,
                                         duration: 0.95)
                    } icon: {
                        HeaderTrophyIcon(isHighlighted: highlightsHeaderTrophies)
                    }
                        .font(.system(size: isPad ? 22 : 15, weight: .bold))
                        .foregroundStyle(character.deepColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(character.deepColor)
                // A player's name gets the available width before the flexible
                // gap does, so short names do not wrap unnecessarily.
                .layoutPriority(1)

                Spacer(minLength: 8)

                // Streak lives to the right, capped to about a third of the row.
                CompactStreakView(accent: character.deepColor) {
                    // The first tap on the streak is a natural, low-pressure
                    // moment to ask about reminders. The goal picker opens only
                    // after the prompt is answered, so they never fight for the
                    // screen; every later tap opens it immediately.
                    NotificationManager.shared.requestAuthorizationOnStreakTap {
                        showGoalPicker = true
                    }
                }
                // Fixed width per idiom; the module centres itself vertically in
                // the row (which is `.center`-aligned), so its height no longer
                // has to track the name/trophy column beside it.
                .frame(width: isPad ? 150 : 106)
                // Keep the popover attached to the streak control itself. When
                // this lived on the screen-wide container, changing the period
                // rebuilt the picker and let SwiftUI fall back to that
                // container's centre as the presentation source.
                .popover(isPresented: $showGoalPicker, arrowEdge: .top) {
                    DailyGoalPicker(theme: character)
                        .padding()
                        .presentationCompactAdaptation(.popover)
                }
            }

            Divider().overlay(character.deepColor.opacity(0.22))

            VStack(spacing: menuControlSpacing) {
                HStack(alignment: .center) {
                    Text(selectedFilter.title)
                    .font(.system(size: isPad ? 30 : 20, weight: .heavy, design: .rounded))
                    Label {
                        let cat = headerCount(start: scoreCelebration?.categoryStart,
                                              current: categoryTrophies)
                        TrophyCountText(from: cat.from,
                                         to: cat.to,
                                         celebrationStartedAt: cat.at,
                                         suffix: answerHelper ? "*" : "",
                                         delay: 0,
                                         duration: 0.95)
                    } icon: {
                        HeaderTrophyIcon(isHighlighted: highlightsHeaderTrophies)
                            .reportAnchor("categoryTrophy")
                    }
                        .font(.system(size: isPad ? 22 : 15, weight: .bold))
                    Spacer()
                }
                .foregroundStyle(character.deepColor)

                filterPicker

                if selectedFilter == .mixed {
                    supermixCategoryPicker
                } else {
                    menuModePicker
                }

                helperModeRow
            }
        }
        .padding(isPad ? 22 : 14)
        // Fill and outline both sit behind the card's content, so the character
        // can spring up in front of the card's top edge instead of ducking
        // behind it. The content is inset by the padding, so the outline still
        // frames the card at rest.
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.white.opacity(0.76))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white.opacity(0.9), lineWidth: 1)
                }
        }
        .shadow(color: character.deepColor.opacity(0.12), radius: 14, y: 7)
    }

    private func menuFilterButton(_ filter: MenuFilter) -> some View {
        let isSelected = filter == selectedFilter
        return Button {
            AppAudio.shared.playMenuTap()
            // Tapping the already-selected topic reveals its info pop-out
            // instead of re-selecting it (which did nothing before).
            if isSelected {
                showInfoPopup(.filter(filter), anchorKey: "filter.\(filter.rawValue)")
            } else {
                clearMaximumCountPreview()
                // Keep selection animation local to the button below. A global
                // menu transaction can retarget an in-flight character jump.
                triggerCharacterJump(big: true)
                // Commit the heavier level-grid swap one runloop later, after
                // Core Animation has received the launch pose.
                DispatchQueue.main.async {
                    menuFilterRaw = filter.rawValue
                }
            }
        } label: {
            menuFilterIcon(filter, isSelected: isSelected)
            .frame(maxWidth: .infinity)
            .frame(height: filterButtonDiameter)
            .background(isSelected ? character.deepColor : .white.opacity(0.7), in: Circle())
            .overlay(Circle().stroke(character.deepColor.opacity(isSelected ? 0 : 0.25), lineWidth: 1))
            .reportAnchor("filter.\(filter.rawValue)")
            .animation(.snappy(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
        .highPriorityGesture(
            LongPressGesture(minimumDuration: 2)
                .onEnded { _ in
                    guard filter == .mixed, isSelected else { return }
                    previewMaximumCountBadge()
                }
        )
    }

    /// Align the outer topic controls with the full-width controls underneath.
    /// The circles retain their established tap size while the gaps absorb the
    /// available width on both iPhone and iPad.
    private var filterPicker: some View {
        HStack(spacing: 0) {
            ForEach(Array(MenuFilter.allCases.enumerated()), id: \.element.id) { index, filter in
                menuFilterButton(filter)
                    .frame(width: filterButtonDiameter, height: filterButtonDiameter)

                if index < MenuFilter.allCases.count - 1 {
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func menuFilterIcon(_ filter: MenuFilter, isSelected: Bool) -> some View {
        // Every topic renders the same way: a bare glyph tinted white on the
        // selected (solid) button and the theme colour on the outlined ones.
        // Per-symbol point sizes even out the differing optical heights (the
        // filled star reads large, the percent glyph tall) and a shared height
        // box keeps them all vertically centred on the same line.
        let size: CGFloat
        switch filter {
        case .mixed:       size = 17 * menuScale   // star.fill
        case .percentages: size = 19 * menuScale   // percent
        default:           size = 21 * menuScale   // + − × ÷
        }
        return Image(systemName: filter.icon)
            .font(.system(size: size, weight: .bold))
            .frame(height: 24 * menuScale)
            .foregroundStyle(isSelected ? .white : character.deepColor)
    }

    /// Reconciles persistent progress once, in small main-actor batches. Menu
    /// rendering then reads this in-memory snapshot instead of touching
    /// UserDefaults/iCloud for every card and every selection change.
    private func refreshHomeProgress() {
        guard !defersHomeProgressRefresh else { return }
        homeProgressGeneration += 1
        let generation = homeProgressGeneration
        let variants = LevelCatalog.byCategory.values
            .flatMap { $0 }
            .flatMap(\.allModeVariants)

        Task { @MainActor in
            // Let the currently requested character/menu frame commit first.
            try? await Task.sleep(nanoseconds: 1_000_000)
            var snapshot = HomeProgressSnapshot()

            for (index, level) in variants.enumerated() {
                guard generation == homeProgressGeneration else { return }
                let id = level.id
                // Some catalog paths can describe the same variant. Never pay
                // the reconciliation cost twice in one snapshot.
                guard snapshot.levels[id] == nil else { continue }

                snapshot.levels[id] = readHomeProgress(for: level)

                // Bound each main-thread slice so Core Animation gets regular
                // opportunities to present even during a full cloud refresh.
                if index.isMultiple(of: 8) {
                    try? await Task.sleep(nanoseconds: 1_000_000)
                }
            }

            guard generation == homeProgressGeneration else { return }
            homeProgress = snapshot
            CharacterUnlockStore.trophyTotal = totalTrophies(in: snapshot)
            snapshot.persist()
        }
    }

    /// Reads the complete cache entry for one level. This is deliberately
    /// shared by the background reconciliation and the lightweight return
    /// path after gameplay.
    private func readHomeProgress(for level: LevelConfig) -> HomeLevelProgress {
        let id = level.id
        return HomeLevelProgress(
            normalBest: ProgressStore.bestScore(levelID: id),
            helperBest: ProgressStore.helperOnlyBestScore(levelID: id),
            normalMaximumCount: ProgressStore.maxCompletionCount(
                levelID: id, helperEnabled: false
            ),
            helperMaximumCount: ProgressStore.maxCompletionCount(
                levelID: id, helperEnabled: true
            ),
            pausedNormal: PausedGameStore.shared.pausedScore(
                forLevelID: id, includingHelper: false
            ),
            pausedIncludingHelper: PausedGameStore.shared.pausedScore(
                forLevelID: id, includingHelper: true
            ),
            isPausedInCurrentLifeMode: PausedGameStore.shared.hasPausedSession(
                for: level, mode: lifeMode
            )
        )
    }

    /// The first-run explanation is useful, but its full-screen overlay should
    /// never animate at the same time as the score returning to the menu. When
    /// `onFinished` is supplied it runs the moment the hint is dismissed (by the
    /// timer or a tap), which is how the first-play return waits for the hint to
    /// be read before starting its celebration.
    private func scheduleTutorialScoreHint(for levelID: String,
                                           after delay: TimeInterval,
                                           onFinished: (() -> Void)? = nil) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard selection == nil, tutorial.shouldShowScoreHint else {
                onFinished?()
                return
            }
            scoreHintLevelID = levelID
            afterScoreHint = onFinished
            withAnimation(.easeOut(duration: 0.25)) {
                showTutorialScoreHint = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
                finishTutorialScoreHint()
            }
        }
    }

    /// Hides the score hint and runs whatever was waiting on it. Safe to call
    /// from both the auto-dismiss timer and a manual tap; the second call is a
    /// no-op because the hint is already gone.
    private func finishTutorialScoreHint() {
        guard showTutorialScoreHint else { return }
        withAnimation(.easeOut(duration: 0.2)) { showTutorialScoreHint = false }
        scoreHintLevelID = nil
        tutorial.consumeScoreHint()
        let continuation = afterScoreHint
        afterScoreHint = nil
        continuation?()
    }

    /// Installs the new score and starting values atomically, then runs the
    /// return celebration: the card counts up (and, at max, reveals its gold
    /// border), after which a trophy flies up to the category header where the
    /// category and grand totals count up together.
    @MainActor
    private func installAndCelebrate(celebration: ScoreCelebration,
                                     levelID: String,
                                     snapshot: HomeProgressSnapshot,
                                     earnedMore: Bool,
                                     targetScore: Int,
                                     showTutorialHintAfter: Bool) {
        guard selection == nil, lastOpenedLevelID == levelID else {
            defersHomeProgressRefresh = false
            refreshHomeProgress()
            return
        }

        // Re-stamp the celebration to *now*: on the tutorial return this method
        // runs only after the score hint has been read, so the timestamp taken
        // when the game cover dismissed is already stale. Every time-driven view
        // keys off this value, so stamping it here makes the count-up and the
        // return outline start from zero elapsed for every return, tutorial or
        // not. The subsequent card sequence also derives its delay from it.
        var celebration = celebration
        celebration.startedAt = Date()

        // The card's own animations start from an already-live hierarchy,
        // without recreating the entire menu via refreshID.
        withTransaction(Transaction(animation: nil)) {
            homeProgress = snapshot
            let newTotal = totalTrophies(in: snapshot)
            CharacterUnlockStore.trophyTotal = newTotal
            let newlyReached = CharacterUnlockStore.unannouncedMilestones(at: newTotal)
                .filter { $0.threshold > celebration.totalStart }
            for milestone in newlyReached where !pendingCharacterUnlocks.contains(milestone) {
                pendingCharacterUnlocks.append(milestone)
            }
            headerTrophyArrival = nil
            flyingTrophy = nil
            reachedMaximumCelebrationID = nil
            finishedCardCelebrations.remove(celebration.id)
            if earnedMore { scoreCelebration = celebration }
        }

        guard earnedMore else {
            defersHomeProgressRefresh = false
            if showTutorialHintAfter {
                scheduleTutorialScoreHint(for: levelID, after: 0.05) {
                    // The state is already hidden, but its 0.2-second fade must
                    // finish before StoreKit is allowed to present.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        if !presentPendingCharacterUnlockIfPossible() {
                            requestReviewAfterSettledReturn()
                        }
                    }
                }
            } else {
                if !presentPendingCharacterUnlockIfPossible() {
                    requestReviewAfterSettledReturn()
                }
            }
            return
        }

        // Trophies were earned: play the home-screen trophy sound as the card
        // begins to count them up.
        AppAudio.shared.playTrophyMenu()

        // The card itself reports when its last animation has settled. Starting
        // the flight from that callback (instead of a guessed timer) keeps the
        // order deterministic even when dismissal/rendering takes longer.
        scheduleAuthoritativeCardSequence(
            celebration: celebration,
            targetScore: targetScore
        )
    }

    /// Drives every improved-score sequence from ContentView, whose identity
    /// survives card/grid rebuilds. Ordinary improvements wait for their score
    /// pulse; first-max improvements additionally wait for the crown, side
    /// decorations and outline before either one may launch its flying trophy.
    @MainActor
    private func scheduleAuthoritativeCardSequence(
        celebration: ScoreCelebration,
        targetScore: Int
    ) {
        let maximum = ProgressStore.maximumTrophies(forLevelID: celebration.levelID)
        guard celebration.scoreDidIncrease,
              targetScore > celebration.levelStart else { return }

        let displayedTarget = min(targetScore, maximum)
        let displayedStart = min(celebration.levelStart, maximum)
        let difference = max(1, displayedTarget - displayedStart)
        let finalRoundingDistance = 0.5 / Double(difference)
        let progressWhenFinalValueAppears = 1 - pow(finalRoundingDistance, 1.0 / 3.0)
        let visualLandingOffset = 0.3 + 0.78 * progressWhenFinalValueAppears
        let delay = max(
            0,
            celebration.startedAt
                .addingTimeInterval(visualLandingOffset)
                .timeIntervalSinceNow
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard scoreCelebration?.id == celebration.id else { return }
            let crossesIntoMaximum = celebration.levelStart < maximum
                && targetScore >= maximum
            if crossesIntoMaximum {
                reachedMaximumCelebrationID = celebration.id
            }

            // The normal trophy pulse retracts after 0.62 s; leave a short
            // settling beat. A first max needs longer for its complete reveal.
            let cardSettleDelay: TimeInterval = crossesIntoMaximum ? 1.12 : 0.72
            DispatchQueue.main.asyncAfter(deadline: .now() + cardSettleDelay) {
                guard scoreCelebration?.id == celebration.id else { return }
                cardCelebrationDidFinish(celebration)
            }
        }
    }

    @MainActor
    private func cardCelebrationDidFinish(_ celebration: ScoreCelebration) {
        guard scoreCelebration?.id == celebration.id,
              !finishedCardCelebrations.contains(celebration.id) else { return }
        finishedCardCelebrations.insert(celebration.id)

        let categoryGrew = categoryTrophies > celebration.categoryStart
        let willFly = celebration.scoreDidIncrease && categoryGrew
        let flightDuration: TimeInterval = 0.55

        // On higher levels the header (grand total) has scrolled off the top of
        // the menu, so both the flight and the count-up used to happen unseen.
        // Bring the header back on-screen first, then let the anchors settle
        // before launching the flight.
        let scrollDelay: TimeInterval = willFly ? 0.42 : 0
        if willFly {
            withAnimation(.easeInOut(duration: 0.32)) {
                scrollProxy?.scrollTo(Self.headerScrollID, anchor: .top)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + scrollDelay) {
                guard scoreCelebration?.id == celebration.id else { return }
                launchTrophyFlight(for: celebration, duration: flightDuration)
            }
        }

        let remainingLifetime: TimeInterval = willFly
            ? scrollDelay + flightDuration + 0.95 + 0.3
            : 0.3
        DispatchQueue.main.asyncAfter(deadline: .now() + remainingLifetime) {
            guard scoreCelebration?.id == celebration.id else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                scoreCelebration = nil
            }
            headerTrophyArrival = nil
            reachedMaximumCelebrationID = nil
            finishedCardCelebrations.remove(celebration.id)
            // Keep the all-level cloud reconciliation away from the
            // celebration's fade-out.
            let refreshDelay = 0.35
            DispatchQueue.main.asyncAfter(deadline: .now() + refreshDelay) {
                guard selection == nil, lastOpenedLevelID == celebration.levelID else {
                    defersHomeProgressRefresh = false
                    return
                }
                defersHomeProgressRefresh = false
                refreshHomeProgress()
                if !presentPendingCharacterUnlockIfPossible() {
                    requestReviewAfterSettledReturn()
                }
            }
        }
    }

    /// Presents one earned character only after the home return sequence has
    /// completely left the screen. Additional milestones remain queued and
    /// appear after the player closes the current collection sheet.
    @MainActor
    @discardableResult
    private func presentPendingCharacterUnlockIfPossible() -> Bool {
        guard selection == nil,
              scoreCelebration == nil,
              flyingTrophy == nil,
              !showTutorialScoreHint,
              !showPremium,
              !showNameEditor,
              infoPopup == nil,
              let milestone = pendingCharacterUnlocks.first else {
            return false
        }
        pendingCharacterUnlocks.removeFirst()
        CharacterUnlockStore.markAnnounced(milestone)
        presentCharacterUnlock(milestone, isPreview: false)
        return true
    }

    @MainActor
    private func presentCharacterUnlock(_ milestone: TrophyCharacterMilestone,
                                        isPreview: Bool) {
        premiumInitialCharacterID = milestone.characterID
        celebratedCharacterUnlock = milestone
        isCharacterUnlockPreview = isPreview
        showPremium = true
    }

    private func openCharacterCollection(initialCharacterID: String? = nil) {
        premiumInitialCharacterID = initialCharacterID
        celebratedCharacterUnlock = nil
        isCharacterUnlockPreview = false
        showPremium = true
    }

    /// Uses StoreKit's native prompt only after the presenting menu is active
    /// and every return animation or overlay has left the screen. If the app is
    /// backgrounded mid-sequence, scenePhase retries the pending opportunity.
    @MainActor
    private func requestReviewAfterSettledReturn() {
        guard scenePhase == .active,
              selection == nil,
              scoreCelebration == nil,
              flyingTrophy == nil,
              !showTutorialScoreHint,
              !showPremium,
              !showNameEditor,
              infoPopup == nil,
              ReviewRequestCoordinator.shared.menuReturnDidSettle() else {
            return
        }
        requestReview()
    }

    /// Sends the trophy copy from the celebrating card up to the category
    /// header. If either endpoint is unknown (the card scrolled off-screen),
    /// the reward lands on the header immediately instead.
    @MainActor
    private func launchTrophyFlight(for celebration: ScoreCelebration, duration: TimeInterval) {
        guard scoreCelebration?.id == celebration.id else { return }
        guard let destination = controlAnchors["categoryTrophy"] else {
            landHeaderTrophies(for: celebration)
            return
        }
        // If scrolling the header into view moved the earning card completely
        // outside the viewport, launch from a sensible on-screen position.
        // A visible glyph must always win: using only its distance from the
        // header incorrectly replaced real launch points on tall screens.
        let fallbackSource = CGRect(x: destination.midX - 8,
                                    y: destination.maxY + 420, width: 16, height: 16)
        // Only launch from the real card glyph when it is both visible and
        // genuinely below the header trophy: the trophy always travels upward
        // to the subcategory total. If the earning card scrolled off, or sits at
        // or above the header (e.g. the player was scrolled deep into the level
        // list before the header was brought back on-screen), start from the
        // fallback point below the header so the arc still reads as "up".
        let source = cardTrophyAnchors[celebration.levelID].flatMap { candidate -> CGRect? in
            let visible = homeViewportFrame.isEmpty || homeViewportFrame.intersects(candidate)
            let belowHeader = candidate.midY > destination.midY + 24
            return visible && belowHeader ? candidate : nil
        } ?? fallbackSource
        let cardScale = levelCardHeight / 96
        withTransaction(Transaction(animation: nil)) {
            flyingTrophy = FlyingTrophy(
                celebrationID: celebration.id,
                source: source,
                destination: destination,
                sourcePointSize: 9 * cardScale,
                destPointSize: isPad ? 22 : 15,
                arcHeight: isPad ? 40 : 26,
                color: character.deepColor,
                startedAt: Date(),
                duration: duration
            )
        }
        // The whoosh accompanies the trophy for the duration of its flight; the
        // existing arrival sound (`playTrophyTotal`) still fires when it lands
        // and the header totals begin to count up.
        AppAudio.shared.playTrophyFlight()
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            if flyingTrophy?.celebrationID == celebration.id { flyingTrophy = nil }
            landHeaderTrophies(for: celebration)
        }
    }

    /// Merges the reward into the header: the category and grand totals count up
    /// and the trophy icon gives a small welcoming pulse.
    @MainActor
    private func landHeaderTrophies(for celebration: ScoreCelebration) {
        guard scoreCelebration?.id == celebration.id else { return }
        headerTrophyArrival = Date()
        // The grand total at the top starts ticking up now — its own sound.
        AppAudio.shared.playTrophyTotal()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.56)) {
            highlightsHeaderTrophies = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.66) {
            withAnimation(.easeOut(duration: 0.24)) {
                highlightsHeaderTrophies = false
            }
        }
    }

    private var totalTrophies: Int {
        totalTrophies(in: homeProgress)
    }

    // Premium levels count toward both totals exactly like the free ones: a
    // trophy earned on e.g. level 23 is a real increase, so its card must launch
    // the flying trophy and the header must count up. Only premium owners can
    // reach these levels (they are locked otherwise, so they contribute 0 for
    // everyone else), and owners can already use every character, so folding
    // them in never changes a locked player's total nor spuriously fires a
    // character-unlock milestone.
    private func totalTrophies(in snapshot: HomeProgressSnapshot) -> Int {
        LevelCatalog.byCategory.values.flatMap { $0 }
            .reduce(0) { $0 + trophiesAcrossPracticeModes(for: $1, snapshot: snapshot) }
    }

    private var categoryTrophies: Int {
        let levels = selectedFilter == .mixed
            ? ChallengeCategory.supermixMenu.flatMap { LevelCatalog.levels(for: $0) }
            : LevelCatalog.levels(for: category)
        return levels
            .reduce(0) { $0 + trophiesAcrossPracticeModes(for: $1) }
    }

    /// The `(from, to, startedAt)` a header trophy counter should use. It holds
    /// the pre-run total while the reward flies up from the card, then counts up
    /// the moment the trophy lands (`headerTrophyArrival`). With no celebration
    /// it simply shows the live value.
    private func headerCount(start: Int?, current: Int) -> (from: Int, to: Int, at: Date?) {
        if let arrival = headerTrophyArrival, let start {
            return (start, current, arrival)
        }
        if scoreCelebration != nil, let start {
            return (start, start, nil)
        }
        return (current, current, nil)
    }

    /// A base level contributes the total of all three practice modes to both
    /// its topic and the player's overall total. The exact variant scores remain
    /// separate on their level cards, but Reeks, Hussel and Gemixt all count.
    /// Supermix has no practice-mode row and therefore contributes each of its
    /// concrete levels exactly once.
    private func trophiesAcrossPracticeModes(for level: LevelConfig) -> Int {
        trophiesAcrossPracticeModes(for: level, snapshot: homeProgress)
    }

    private func trophiesAcrossPracticeModes(for level: LevelConfig,
                                             snapshot: HomeProgressSnapshot) -> Int {
        guard !level.category.isSupermixMenu else {
            return trophies(forExactLevel: level, snapshot: snapshot)
        }
        return level.allModeVariants.reduce(0) {
            $0 + trophies(forExactLevel: $1, snapshot: snapshot)
        }
    }

    /// Score contribution of one exact level+mode id, including a higher paused
    /// score in that same subcategory only.
    private func trophies(forExactLevel level: LevelConfig) -> Int {
        trophies(forExactLevel: level, snapshot: homeProgress)
    }

    private func trophies(forExactLevel level: LevelConfig,
                           snapshot: HomeProgressSnapshot) -> Int {
        let progress = snapshot.value(for: level.id)
        let recorded = answerHelper
            ? max(progress.normalBest, progress.helperBest)
            : progress.normalBest
        let pausedRaw = answerHelper
            ? progress.pausedIncludingHelper
            : progress.pausedNormal
        let paused = capsTrophiesAtThirty
            ? min(ProgressStore.maximumTrophies(for: level), pausedRaw)
            : pausedRaw
        return max(recorded, paused)
    }

    /// Matches the score a level card presents in the current helper mode, so
    /// a highlight always corresponds to a visibly improved score.
    private func displayedScore(forLevelID levelID: String) -> Int {
        let progress = homeProgress.value(for: levelID)
        return answerHelper
            ? max(progress.normalBest, progress.helperBest)
            : progress.normalBest
    }

    private func displayedMaximumCount(forLevelID levelID: String) -> Int {
        let progress = homeProgress.value(for: levelID)
        return answerHelper ? progress.helperMaximumCount : progress.normalMaximumCount
    }

    private func maximumCount(for level: LevelConfig) -> Int {
        if maximumCountPreviewLevelID == level.id, let maximumCountPreview {
            return maximumCountPreview
        }
        if secondMaximumCountPreviewLevelID == level.id, let secondMaximumCountPreview {
            return secondMaximumCountPreview
        }
        return displayedMaximumCount(forLevelID: level.id)
    }

    private func displayedBest(for level: LevelConfig, best: Int) -> Int {
        if maximumCountPreviewLevelID == level.id { return ProgressStore.maximumTrophies(for: level) }
        if secondScorePreviewLevelID == level.id, let secondScorePreview { return secondScorePreview }
        return best
    }

    private func isCelebratingScore(for level: LevelConfig) -> Bool {
        guard let celebration = scoreCelebration,
              celebration.levelID == level.id else { return false }
        return celebration.scoreDidIncrease
    }

    private func previewMaximumCountBadge() {
        let levels = LevelCatalog.levels(for: category).map {
            selectedFilter != .mixed ? $0.variant(menuMode) : $0
        }
        guard levels.count >= 2 else { return }
        let firstLevelID = levels[0].id
        let secondLevelID = levels[1].id
        maximumCountPreviewLevelID = firstLevelID
        secondScorePreviewLevelID = secondLevelID
        secondScorePreview = 49
        showMaximumCountPreview(levelID: firstLevelID, count: 99)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) {
            guard self.maximumCountPreviewLevelID == firstLevelID else { return }
            self.showMaximumCountPreview(levelID: firstLevelID,
                                         count: ProgressStore.maximumCompletionCount)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.7) {
            guard self.maximumCountPreviewLevelID == firstLevelID,
                  self.secondScorePreviewLevelID == secondLevelID else { return }
            self.secondScorePreview = 50
            self.secondMaximumCountPreviewLevelID = secondLevelID
            self.secondMaximumCountPreview = 1
            self.showLevelTwoMaximumPreview(levelID: secondLevelID)
        }
        // This secret preview deliberately appends the new frog unlock after
        // both existing maximum-count reveals have fully settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.25) {
            guard self.maximumCountPreviewLevelID == firstLevelID,
                  self.secondMaximumCountPreviewLevelID == secondLevelID else { return }
            self.clearMaximumCountPreview()
            self.presentCharacterUnlock(
                TrophyCharacterMilestone(characterID: "frog", threshold: 500),
                isPreview: true
            )
        }
    }

    private func showMaximumCountPreview(levelID: String, count: Int) {
        maximumCountPreview = count
        let celebration = ScoreCelebration(levelID: levelID,
                                           levelStart: displayedScore(forLevelID: levelID),
                                           maximumCountStart: count - 1,
                                           categoryStart: categoryTrophies,
                                           totalStart: totalTrophies,
                                           scoreDidIncrease: false)
        withAnimation(.easeOut(duration: 0.34)) {
            scoreCelebration = celebration
            refreshID = UUID()
        }
    }

    private func showLevelTwoMaximumPreview(levelID: String) {
        let celebration = ScoreCelebration(levelID: levelID,
                                           levelStart: 49,
                                           maximumCountStart: 0,
                                           categoryStart: categoryTrophies,
                                           totalStart: totalTrophies,
                                           scoreDidIncrease: true)
        withAnimation(.easeOut(duration: 0.34)) {
            scoreCelebration = celebration
            refreshID = UUID()
        }
    }

    private func clearMaximumCountPreview() {
        maximumCountPreview = nil
        maximumCountPreviewLevelID = nil
        secondMaximumCountPreview = nil
        secondMaximumCountPreviewLevelID = nil
        secondScorePreview = nil
        secondScorePreviewLevelID = nil
        scoreCelebration = nil
        flyingTrophy = nil
        headerTrophyArrival = nil
        reachedMaximumCelebrationID = nil
    }

    // MARK: Tap-again info pop-out

    /// Shared coordinate space so control anchors, level frames and the
    /// pop-out's own placement all speak in the same points.
    static let homeSpace = "home"
    /// Scroll id of the menu header, so the trophy total can be brought on-screen.
    static let headerScrollID = "menuHeader"

    /// The levels currently on screen (regular + any premium), in the exact
    /// mode the menu shows them — used to resolve a tapped level frame back to
    /// its config so the pop-out can start it directly.
    private var currentLevels: [LevelConfig] {
        LevelCatalog.levels(for: category).map {
            selectedFilter != .mixed ? $0.variant(menuMode) : $0
        }
    }

    private func showInfoPopup(_ kind: InfoPopup.Kind, anchorKey: String) {
        guard let anchor = controlAnchors[anchorKey] else { return }
#if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            infoPopup = InfoPopup(kind: kind, anchor: anchor)
        }
    }

    private func dismissInfoPopup() {
        withAnimation(.easeOut(duration: 0.16)) { infoPopup = nil }
    }

    /// A tap anywhere behind the pop-out. It always closes the pop-out, and if
    /// the tap also lands on something actionable it does that in the same move:
    /// a level card starts it; another topic/order/Supermix control switches to
    /// it. A tap on empty space only closes.
    private func handleInfoBackgroundTap(at point: CGPoint) {
        // A level card: close and start it.
        if let hit = levelFrames.first(where: { $0.value.contains(point) }),
           let level = currentLevels.first(where: { $0.id == hit.key }) {
            dismissInfoPopup()
            selection = LevelSelection(level: level)
            clearMaximumCountPreview()
            return
        }
        // A topic / order / Supermix control: close and switch to it.
        if let hit = controlAnchors.first(where: { $0.value.contains(point) }) {
            dismissInfoPopup()
            applyControlSelection(forKey: hit.key)
            return
        }
        // Empty space: close only.
        dismissInfoPopup()
    }

    /// Apply the selection a control key ("filter.5", "mode.standard",
    /// "super.superBasic") represents. A tap on the already-selected control is
    /// a no-op switch, so it simply closes the pop-out.
    private func applyControlSelection(forKey key: String) {
        guard let dot = key.firstIndex(of: ".") else { return }
        let prefix = key[..<dot]
        let value = String(key[key.index(after: dot)...])
        switch prefix {
        case "filter":
            guard let raw = Int(value), raw != menuFilterRaw else { return }
            clearMaximumCountPreview()
            triggerCharacterJump(big: true)
            DispatchQueue.main.async { menuFilterRaw = raw }
        case "mode":
            guard value != menuModeRaw else { return }
            clearMaximumCountPreview()
            triggerCharacterJump(big: false)
            DispatchQueue.main.async { menuModeRaw = value }
        case "super":
            guard value != supermixCategoryRaw else { return }
            clearMaximumCountPreview()
            triggerCharacterJump(big: false)
            DispatchQueue.main.async { supermixCategoryRaw = value }
        default:
            break
        }
    }

    private func infoPopupOverlay(_ popup: InfoPopup) -> some View {
        GeometryReader { geo in
            // Convert the anchor (in "home" space) into this overlay's local
            // space so the card sits just under the tapped control.
            let localOrigin = geo.frame(in: .named(Self.homeSpace)).origin
            // Let concise explanations stay compact, while allowing longer
            // labels to remain on one line whenever the menu's side margins
            // permit it.
            let cardWidth = InfoPopoutCard.preferredWidth(
                header: popup.header,
                message: popup.body,
                isPad: isPad,
                maximum: geo.size.width - 24
            )
            let anchorMidX = popup.anchor.midX - localOrigin.x
            // The first two operation buttons and the first sequencing button
            // have ample room to their right.  Keep their pop-outs anchored at
            // the control's leading edge so a longer translation grows into
            // that space, rather than pushing further towards the screen edge.
            // The remaining controls retain the centred placement, which lets
            // their cards use the room on their left.
            let expandsRight = popoutExpandsRight(popup.kind)
            let leadingAnchorX = popup.anchor.minX - localOrigin.x
            let rawX = expandsRight ? leadingAnchorX : anchorMidX - cardWidth / 2
            let x = min(max(12, rawX), max(12, geo.size.width - cardWidth - 12))
            let y = popup.anchor.maxY - localOrigin.y + 8

            ZStack(alignment: .topLeading) {
                // Light-dismiss catcher: closes on any tap, and forwards a tap
                // that lands on a level card straight through to start it.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture(coordinateSpace: .named(Self.homeSpace))
                            .onEnded { value in handleInfoBackgroundTap(at: value.location) }
                    )

                // Caret points at the control, measured from the card's centre
                // and kept inside its rounded corners.
                let caretLimit = cardWidth / 2 - 18
                let caret = min(max(anchorMidX - (x + cardWidth / 2), -caretLimit), caretLimit)
                InfoPopoutCard(header: popup.header,
                               message: popup.body,
                               caretOffset: caret,
                               theme: character)
                    .frame(width: cardWidth)
                    .offset(x: x, y: y)
                    .onTapGesture { dismissInfoPopup() }
            }
        }
    }

    private func popoutExpandsRight(_ kind: InfoPopup.Kind) -> Bool {
        switch kind {
        case .filter(.addition), .filter(.subtraction), .mode(.order, _):
            return true
        default:
            return false
        }
    }

    private var menuModePicker: some View {
        // Three equal-width buttons: Reeks · Hussel · Gemixt (Order · Random ·
        // Mixed). The label keeps one line and shrinks to fit, so a longer word
        // in another language still fits three-across without changing the base
        // text size the shorter labels use.
        HStack(spacing: isPad ? 12 : 8) {
            ForEach(PracticeMode.allCases) { mode in
                let isSelected = menuMode == mode
                Button {
                    AppAudio.shared.playMenuTap()
                    if isSelected {
                        showInfoPopup(.mode(mode, selectedFilter.standard), anchorKey: "mode.\(mode.rawValue)")
                    } else {
                        clearMaximumCountPreview()
                        triggerCharacterJump(big: false)
                        DispatchQueue.main.async {
                            menuModeRaw = mode.rawValue
                        }
                    }
                } label: {
                    Text(mode.title(for: selectedFilter.standard))
                        .font(.system(size: isPad ? 22 : 15, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(isSelected ? .white : character.deepColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: modeButtonHeight)
                        .padding(.horizontal, isPad ? 8 : 2)
                        .background(isSelected ? character.deepColor : .white.opacity(0.62), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(character.deepColor.opacity(isSelected ? 0 : 0.28), lineWidth: 1))
                        .reportAnchor("mode.\(mode.rawValue)")
                        .animation(.snappy(duration: 0.2), value: isSelected)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("menu.accessibility.chooseMode \(mode.title(for: selectedFilter.standard))")
            }
        }
    }

    /// The Supermix filter's four buttons, each a self-contained 99-level
    /// category that combines progressively more operations.
    private var supermixCategoryPicker: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: isPad ? 12 : 8), GridItem(.flexible(), spacing: isPad ? 12 : 8)], spacing: isPad ? 12 : 8) {
            ForEach(ChallengeCategory.supermixMenu) { menuCategory in
                let isSelected = supermixCategory == menuCategory
                Button {
                    AppAudio.shared.playMenuTap()
                    if isSelected {
                        showInfoPopup(.superCategory(menuCategory), anchorKey: "super.\(menuCategory.rawValue)")
                    } else {
                        clearMaximumCountPreview()
                        triggerCharacterJump(big: false)
                        DispatchQueue.main.async {
                            supermixCategoryRaw = menuCategory.rawValue
                        }
                    }
                } label: {
                    supermixLabel(menuCategory)
                        .foregroundStyle(isSelected ? .white : character.deepColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .frame(height: isPad ? 84 : 42)
                        .background(isSelected ? character.deepColor : .white.opacity(0.62), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(character.deepColor.opacity(isSelected ? 0 : 0.28), lineWidth: 1))
                        .reportAnchor("super.\(menuCategory.rawValue)")
                        .animation(.snappy(duration: 0.2), value: isSelected)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("menu.accessibility.chooseMode \(menuCategory.symbol)")
            }
        }
    }

    /// The five operators a Supermix button can show, in their fixed order.
    private static let supermixOperators = ["+", "−", "×", "÷", "%"]

    /// How many of `supermixOperators`, from the start, this button shows.
    private func supermixOperatorCount(_ category: ChallengeCategory) -> Int {
        switch category {
        case .superBasic: return 2
        case .superTimes: return 3
        case .superFraction: return 4
        case .superAll: return 5
        default: return 0
        }
    }

    /// The 2×2 grid's left column (superBasic over superFraction) tops out
    /// at 4 operators, the right column (superTimes over superAll) at 5 —
    /// each column reserves that many slots, so its own shorter button
    /// centers within it rather than sizing to its own operator count.
    private func supermixSlotCount(_ category: ChallengeCategory) -> Int {
        switch category {
        case .superBasic, .superFraction: return 4
        default: return 5
        }
    }

    /// Each column reserves a fixed number of slots (see `supermixSlotCount`);
    /// a button with fewer operators than its column centers within them
    /// (superBasic's "+ −" sits in slots 2–3 of 4), while the longest button
    /// per column fills every slot. This keeps shared operators lined up
    /// between the two buttons stacked in the same column. The "%" glyph
    /// also reads visually heavier than the others at the same point size,
    /// so it gets its own smaller size.
    private func supermixLabel(_ category: ChallengeCategory) -> some View {
        let font = Font.system(size: isPad ? 26 : 19, weight: .bold)
        // jens: tweak these two numbers (iPad, iPhone) to resize the "%" glyph.
        let percentFont = Font.system(size: isPad ? 21 : 15, weight: .bold)
        let slotWidth: CGFloat = isPad ? 30 : 20
        let activeCount = supermixOperatorCount(category)
        let totalSlots = supermixSlotCount(category)
        let offset = (totalSlots - activeCount) / 2
        return HStack(spacing: 2) {
            ForEach(0..<totalSlots, id: \.self) { slot in
                let opIndex = slot - offset
                let symbol = (opIndex >= 0 && opIndex < activeCount) ? Self.supermixOperators[opIndex] : ""
                let isPercent = symbol == "%"
                Text(symbol)
                    .font(isPercent ? percentFont : font)
                    .frame(width: isPercent ? slotWidth * 0.8 : slotWidth)
            }
        }
    }

    private var helperModeRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                AppAudio.shared.playMenuTap()
                withAnimation(.easeInOut(duration: 0.28)) {
                    showsOptions.toggle()
                }
            } label: {
                HStack {
                    Label("menu.options", systemImage: "slider.horizontal.3")
                        .font(.system(size: isPad ? 22 : 15, weight: .bold))
                    Spacer()
                    // `chevron.forward` points outward in both LTR and RTL; the
                    // open state rotates it to point down, which is +90° from a
                    // right-pointing chevron but -90° from the mirrored one.
                    Image(systemName: "chevron.forward")
                        .font(.system(size: isPad ? 22 : 15, weight: .bold))
                        .rotationEffect(.degrees(showsOptions ? (layoutDirection == .rightToLeft ? -90 : 90) : 0))
                }
                .foregroundStyle(character.deepColor)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsOptions {
                VStack(alignment: .leading, spacing: 0) {
                    Divider()
                        .overlay(character.deepColor.opacity(0.2))
                        .padding(.top, isPad ? 14 : 9)

                    // Fourth element: an optional SF Symbol shown after the title
                    // (the cap row spells out "Finish at 30 🏆" without the word).
                    let rows: [(String, Binding<Bool>, String, String?)] = [
                        (L("options.capAt30.title"), $capsTrophiesAtThirty,
                         L("options.capAt30.info"), "trophy.fill"),
                        (L("options.unlimitedLives.title"), unlimitedLivesBinding,
                         L("options.unlimitedLives.info"), nil),
                        (L("options.helperMode.title"), $answerHelper,
                         L("options.helperMode.info"), nil),
                    ]
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 {
                            Divider().overlay(character.deepColor.opacity(0.14))
                        }
                        optionRow(row.0, isOn: row.1, info: row.2, trailingIcon: row.3)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, isPad ? 20 : 11)
        .padding(.top, isPad ? 18 : 10)
        // No dead space under the last row when the list is open — keep the
        // header symmetric when it's closed.
        .padding(.bottom, showsOptions ? (isPad ? 8 : 2) : (isPad ? 18 : 10))
        // Same light fill as an unselected filter field, for a calmer panel.
        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(character.deepColor.opacity(0.18), lineWidth: 1))
    }

    /// A settings row: tap the title (or the info icon, or anywhere in the
    /// text area) to expand a short explanation; the toggle works on its own.
    private func optionRow(_ title: String, isOn: Binding<Bool>, info: String,
                           trailingIcon: String? = nil) -> some View {
        let isExpanded = expandedOptionInfo == title
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: isPad ? 12 : 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.28)) {
                        expandedOptionInfo = isExpanded ? nil : title
                    }
                } label: {
                    HStack(spacing: isPad ? 8 : 6) {
                        Text(title)
                            .font(.system(size: isPad ? 22 : 15, weight: .bold))
                            .multilineTextAlignment(.leading)
                        if let trailingIcon {
                            Image(systemName: trailingIcon)
                                .font(.system(size: isPad ? 18 : 13))
                        }
                        Image(systemName: isExpanded ? "info.circle.fill" : "info.circle")
                            .font(.system(size: isPad ? 18 : 13))
                            .foregroundStyle(character.deepColor)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Toggle(title, isOn: isOn)
                    .labelsHidden()
                    .tint(character.deepColor)
                    .scaleEffect(isPad ? 1.3 : 0.8, anchor: .trailing)
                    .accessibilityLabel(title)
                    .onChange(of: isOn.wrappedValue) { newValue in
                        AppAudio.shared.playSwitch(on: newValue)
                    }
            }
            // ~10% taller rows so the list breathes a little more.
            .frame(minHeight: isPad ? 66 : 42)

            if isExpanded {
                Text(info)
                    .font(.system(size: isPad ? 19 : 14, weight: .regular))
                    .lineSpacing(isPad ? 3 : 2)
                    .foregroundStyle(character.deepColor.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, isPad ? 44 : 30)
                    .padding(.bottom, isPad ? 14 : 10)
                    .transition(.opacity)
            }
        }
        .foregroundStyle(character.deepColor)
    }

    /// Toggle for the options list. ON = unlimited lives (free play), OFF
    /// (default) = the standard three-lives game.
    private var unlimitedLivesBinding: Binding<Bool> {
        Binding(
            get: { lifeMode == .unlimited },
            set: { lifeModeRaw = $0 ? LifeMode.unlimited.rawValue : LifeMode.three.rawValue }
        )
    }

    // MARK: Level grid

    private var levelGrid: some View {
        let levels = LevelCatalog.levels(for: category).map {
            selectedFilter != .mixed ? $0.variant(menuMode) : $0
        }
        let regular = levels.filter { !$0.requiresPremium }
        let premiumLevels = levels.filter { $0.requiresPremium }
        let hasProgress = levels.contains {
            let progress = homeProgress.value(for: $0.id)
            return max(progress.normalBest, progress.helperBest) > 0
        }
        let recommendedID = hasProgress ? nil : regular.first?.id

        return VStack(alignment: .leading, spacing: 14) {
            AdaptiveLevelGrid(spacing: levelGridSpacing,
                              minimumCardWidth: isPad ? 180 : 104,
                              maximumColumns: isPad ? 3 : .max,
                              cardHeight: levelCardHeight) {
                ForEach(regular) { level in
                    let progress = homeProgress.value(for: level.id)
                    let normalBest = displayedBest(for: level,
                                                    best: progress.normalBest)
                    LevelCardView(level: level,
                                  status: status(for: level, recommendedID: recommendedID),
                                  best: normalBest,
                                  pausedBest: answerHelper
                                      ? progress.pausedIncludingHelper
                                      : progress.pausedNormal,
                                  helperBest: progress.helperBest,
                                  showsHelperMarker: answerHelper,
                                  showsTrophies: true,
                                  isPaused: progress.isPausedInCurrentLifeMode,
                                  scoreCelebrationStart: scoreCelebration?.levelID == level.id
                                      ? scoreCelebration?.levelStart : nil,
                                  isCelebratingNewScore: isCelebratingScore(for: level),
                                  showsTutorialScoreFocus: showTutorialScoreHint
                                      && scoreHintLevelID == level.id,
                                  returnFocusStartedAt: scoreCelebration?.levelID == level.id
                                      ? scoreCelebration?.startedAt : nil,
                                  maximumCount: maximumCount(for: level),
                                  maximumCountCelebrationStart: scoreCelebration?.levelID == level.id
                                      ? scoreCelebration?.maximumCountStart : nil,
                                  isCelebratingMaximumCount: scoreCelebration?.levelID == level.id
                                      && maximumCount(for: level) > (scoreCelebration?.maximumCountStart ?? 0),
                                  hasExternallyReachedFirstMax:
                                      reachedMaximumCelebrationID == scoreCelebration?.id
                                      && scoreCelebration?.levelID == level.id,
                                  celebrationID: scoreCelebration?.id,
                                  cardHeight: levelCardHeight,
                                  theme: character,
                                  onCelebrationFinished: { celebrationID in
                                      guard let celebration = scoreCelebration,
                                            celebration.id == celebrationID else { return }
                                      cardCelebrationDidFinish(celebration)
                                  }) {
                        selection = LevelSelection(level: level)
                        clearMaximumCountPreview()
                    }
                    .reportLevelFrame(level.id)
                }
            }

            if !premiumLevels.isEmpty {
                premiumSection(premiumLevels)
            }
        }
    }

    private func status(for level: LevelConfig, recommendedID: String?) -> LevelCardStatus {
        if level.requiresPremium && !premium.isPremium {
            return .locked(progress: 0)
        }
        if homeProgress.value(for: level.id).normalBest >= ProgressStore.completionThreshold {
            return .completed
        }
        if level.id == recommendedID {
            return .recommended
        }
        return .available
    }

    @ViewBuilder
    private func premiumSection(_ levels: [LevelConfig]) -> some View {
        if premium.isPremium {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    Rectangle()
                        .fill(character.deepColor.opacity(0.28))
                        .frame(height: 1.5)
                    HStack(spacing: 5) {
                        Text(premiumSectionTitle)
                            .font(.subheadline.weight(.bold))
                        Image(systemName: "crown.fill")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(character.deepColor)
                    .fixedSize()
                    Rectangle()
                        .fill(character.deepColor.opacity(0.28))
                        .frame(height: 1.5)
                }

                AdaptiveLevelGrid(spacing: levelGridSpacing,
                                  minimumCardWidth: isPad ? 180 : 104,
                                  maximumColumns: isPad ? 3 : .max,
                                  cardHeight: levelCardHeight) {
                    ForEach(levels) { level in
                        let progress = homeProgress.value(for: level.id)
                        let normalBest = displayedBest(for: level,
                                                        best: progress.normalBest)
                        LevelCardView(level: level,
                                      status: status(for: level, recommendedID: nil),
                                      best: normalBest,
                                      pausedBest: answerHelper
                                          ? progress.pausedIncludingHelper
                                          : progress.pausedNormal,
                                      helperBest: progress.helperBest,
                                      showsHelperMarker: answerHelper,
                                      showsTrophies: true,
                                      isPaused: progress.isPausedInCurrentLifeMode,
                                      scoreCelebrationStart: scoreCelebration?.levelID == level.id
                                          ? scoreCelebration?.levelStart : nil,
                                      isCelebratingNewScore: isCelebratingScore(for: level),
                                      showsTutorialScoreFocus: showTutorialScoreHint
                                          && scoreHintLevelID == level.id,
                                      returnFocusStartedAt: scoreCelebration?.levelID == level.id
                                          ? scoreCelebration?.startedAt : nil,
                                      maximumCount: maximumCount(for: level),
                                      maximumCountCelebrationStart: scoreCelebration?.levelID == level.id
                                          ? scoreCelebration?.maximumCountStart : nil,
                                      isCelebratingMaximumCount: scoreCelebration?.levelID == level.id
                                          && maximumCount(for: level) > (scoreCelebration?.maximumCountStart ?? 0),
                                      hasExternallyReachedFirstMax:
                                          reachedMaximumCelebrationID == scoreCelebration?.id
                                          && scoreCelebration?.levelID == level.id,
                                      celebrationID: scoreCelebration?.id,
                                      cardHeight: levelCardHeight,
                                      theme: character,
                                      onCelebrationFinished: { celebrationID in
                                          guard let celebration = scoreCelebration,
                                                celebration.id == celebrationID else { return }
                                          cardCelebrationDidFinish(celebration)
                                      }) {
                            selection = LevelSelection(level: level)
                            clearMaximumCountPreview()
                        }
                        .reportLevelFrame(level.id)
                    }
                }
            }
        } else {
            Button {
                openCharacterCollection()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: isPad ? 24 : 17, weight: .bold))
                        .foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("menu.moreLevels")
                            .font(.system(size: isPad ? 20 : 15, weight: .bold))
                            .foregroundStyle(.white)
                        Text("menu.unlockWithPremium")
                            .font(.system(size: isPad ? 16 : 12, weight: .regular))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    Spacer()
                    Image(systemName: "chevron.forward")
                        .font(.system(size: isPad ? 20 : 15, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        // Match the chevron's right edge with the options
                        // panel above: that panel is inset once by the menu
                        // card and once by its own horizontal padding.
                        .padding(.trailing, isPad ? 22 : 11)
                }
                .padding(isPad ? 20 : 14)
                .background(
                    LinearGradient(colors: [character.color, character.deepColor],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 14)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Tap-again info pop-out

/// The data behind the little themed card shown when the already-selected
/// topic or order is tapped again. `anchor` is the tapped control's frame in
/// the shared "home" coordinate space.
struct InfoPopup: Identifiable {
    enum Kind: Equatable {
        case filter(MenuFilter)
        case mode(PracticeMode, ChallengeCategory)
        case superCategory(ChallengeCategory)
    }

    let kind: Kind
    let anchor: CGRect

    var id: String {
        switch kind {
        case .filter(let f):        return "filter.\(f.rawValue)"
        case .mode(let m, _):       return "mode.\(m.rawValue)"
        case .superCategory(let c): return "super.\(c.rawValue)"
        }
    }

    /// The grouping label ("Types of problems" / "Order" / "Parts" / "Type").
    var header: String {
        switch kind {
        case .filter, .superCategory: return L("info.filter.header")
        case .mode(let m, let c):     return m.infoHeader(for: c)
        }
    }

    /// The one-line description of the specific selection.
    var body: String {
        switch kind {
        case .filter(let f):        return f.infoBody
        case .mode(let m, let c):   return m.infoBody(for: c)
        case .superCategory(let c): return c.supermixInfoBody
        }
    }
}

/// A small caret-topped card styled to match the menu panels: a faint white
/// fill, a hairline theme stroke and a soft shadow. `caretOffset` places the
/// pointer over the control the card belongs to.
private struct InfoPopoutCard: View {
    let header: String
    let message: String
    let caretOffset: CGFloat
    let theme: AnimalCharacter
    private var isPad: Bool { AppLayout.isPad }

    /// Width needed for the header or message, including the card's horizontal
    /// padding. Longer messages deliberately use the narrowest width that still
    /// fits them on two lines, instead of making the pop-out screen-wide.
    static func preferredWidth(header: String,
                               message: String,
                               isPad: Bool,
                               maximum: CGFloat) -> CGFloat {
#if canImport(UIKit)
        let headerFont = UIFont.systemFont(ofSize: isPad ? 14 : 11, weight: .heavy)
        let messageFont = UIFont.systemFont(ofSize: isPad ? 21 : 16, weight: .bold)
        // `Text(header)` adds 0.6 points between every pair of letters below.
        // Include that tracking here as well, otherwise headings such as
        // "Types of problems" can be measured a little too narrowly and wrap
        // even when the pop-out has room to grow horizontally.
        let uppercasedHeader = header.uppercased()
        let headerTracking = CGFloat(max(0, uppercasedHeader.count - 1)) * 0.6
        let headerWidth = (uppercasedHeader as NSString)
            .size(withAttributes: [.font: headerFont]).width + headerTracking
        let messageString = message as NSString
        let messageWidth = messageString
            .size(withAttributes: [.font: messageFont]).width
        let horizontalPadding: CGFloat = isPad ? 36 : 28
        let maximumContentWidth = max(1, maximum - horizontalPadding)

        // Keep short explanations on one line. For longer translations, find
        // the smallest content width that needs no more than two lines. This
        // keeps the second line from leaving a large empty tail in the card.
        if max(headerWidth, messageWidth) <= maximumContentWidth {
            return ceil(max(headerWidth, messageWidth) + horizontalPadding)
        }

        var lowerBound = min(maximumContentWidth, max(headerWidth, isPad ? 220 : 170))
        var upperBound = maximumContentWidth
        let twoLineHeight = messageFont.lineHeight * 2.05

        for _ in 0..<9 {
            let candidate = (lowerBound + upperBound) / 2
            let measured = messageString.boundingRect(
                with: CGSize(width: candidate, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: messageFont],
                context: nil
            )
            if measured.height <= twoLineHeight {
                upperBound = candidate
            } else {
                lowerBound = candidate
            }
        }

        return ceil(upperBound + horizontalPadding)
#else
        return min(isPad ? 340 : 250, maximum)
#endif
    }

    var body: some View {
        VStack(spacing: 0) {
            Triangle()
                .fill(.white)
                .frame(width: 18, height: 9)
                .overlay(alignment: .bottom) {
                    // Hide the seam where the caret meets the card body.
                    Rectangle().fill(.white).frame(height: 1).padding(.horizontal, 2)
                }
                .offset(x: caretOffset)

            VStack(alignment: .leading, spacing: isPad ? 5 : 3) {
                Text(header.uppercased())
                    .font(.system(size: isPad ? 14 : 11, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(theme.deepColor.opacity(0.55))
                Text(message)
                    .font(.system(size: isPad ? 21 : 16, weight: .bold))
                    .foregroundStyle(theme.deepColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, isPad ? 18 : 14)
            .padding(.vertical, isPad ? 14 : 11)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(theme.deepColor.opacity(0.18), lineWidth: 1))
        }
        .shadow(color: theme.deepColor.opacity(0.22), radius: 14, y: 6)
    }
}

/// An upward-pointing triangle for the pop-out caret.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Frames of the on-screen level cards, keyed by level id, in "home" space.
private struct LevelFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Frames of the tappable topic/order controls, keyed by control id.
private struct ControlAnchorKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Frames (in "home" space) of the small trophy glyph on each level card, keyed
/// by level id. These are the launch points for the trophy that flies up to the
/// category header when a level earns more.
private struct CardTrophyAnchorKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// The visible bounds of the home screen in the same coordinate space as the
/// trophy anchors. This distinguishes a genuinely off-screen card from a
/// visible card that merely sits far below the header on a tall display.
private struct HomeViewportFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private extension View {
    /// Report this control's frame (in "home" space) so the info pop-out can
    /// anchor to it.
    func reportAnchor(_ key: String) -> some View {
        background(GeometryReader { geo in
            Color.clear.preference(key: ControlAnchorKey.self,
                                   value: [key: geo.frame(in: .named(ContentView.homeSpace))])
        })
    }

    /// Report this card's trophy-glyph frame (in "home" space) so the flying
    /// trophy can start exactly overlapping it.
    func reportCardTrophy(_ id: String) -> some View {
        background(GeometryReader { geo in
            Color.clear.preference(key: CardTrophyAnchorKey.self,
                                   value: [id: geo.frame(in: .named(ContentView.homeSpace))])
        })
    }

    /// Report this level card's frame (in "home" space) so a background tap
    /// can start it while the info pop-out is open.
    func reportLevelFrame(_ id: String) -> some View {
        background(GeometryReader { geo in
            Color.clear.preference(key: LevelFrameKey.self,
                                   value: [id: geo.frame(in: .named(ContentView.homeSpace))])
        })
    }
}

// MARK: - Playtime bar

/// A single daily streak goal. Tapping it offers a compact goal picker.
struct PlaytimeBar: View {
    let accent: Color
    var isEmbedded = false
    let action: () -> Void
    @ObservedObject private var tracker = PlaytimeTracker.shared

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "flame.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(accent, in: Circle())

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("streak.daily")
                            .font(.caption.weight(.heavy))
                        Spacer()
                        Text("common.minutesShort \(tracker.todayMinutes) \(tracker.dailyGoalMinutes)")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(accent)

                    streakProgressBar

                    Text("streak.daysInARow \(tracker.streakDays)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(accent.opacity(0.78))
                }

                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.white.opacity(isEmbedded ? 0.52 : 0.68), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(accent.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("streak.accessibility.daily \(tracker.todayMinutes) \(tracker.dailyGoalMinutes)")
        .accessibilityHint("streak.accessibility.chooseDailyGoal")
    }

    private var dailyProgress: Double {
        min(1, Double(tracker.todayMinutes) / Double(max(1, tracker.dailyGoalMinutes)))
    }

    private var streakProgressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(accent.opacity(0.13))
                Capsule()
                    .fill(LinearGradient(colors: [accent.opacity(0.65), accent], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(7, proxy.size.width * dailyProgress))
            }
        }
        .frame(height: 8)
    }
}

/// Compact streak widget for the top-right of the menu card: the streak-day
/// count with a flame, a horizontal progress line for today's minutes toward
/// the goal, and the minutes underneath. No border — it's part of the card.
///
/// The module sizes to its own content and centres itself in the header row,
/// so its internal spacing never stretches to track a one- or two-line name
/// beside it — only its vertical centring shifts. Every metric derives from a
/// single scale factor, so the proportions hold on both iPhone and iPad.
struct CompactStreakView: View {
    let accent: Color
    let action: () -> Void
    @ObservedObject private var tracker = PlaytimeTracker.shared
    @AppStorage("ui.goalPeriod") private var goalPeriodRaw = GoalPeriod.weekly.rawValue

    private var goalPeriod: GoalPeriod { GoalPeriod(rawValue: goalPeriodRaw) ?? .weekly }
    private var isPad: Bool { AppLayout.isPad }

    // One factor drives every dimension, so the widget keeps its proportions
    // when it scales up for the larger iPad layout.
    private var scale: CGFloat { isPad ? 1.4 : 1 }
    private var railWidth: CGFloat { 74 * scale }
    private var rowSpacing: CGFloat { 5 * scale }

    private var progressMinutes: Int {
        goalPeriod == .weekly ? tracker.weekMinutes : tracker.todayMinutes
    }

    private var goalMinutes: Int {
        goalPeriod == .weekly ? tracker.weeklyGoalMinutes : tracker.dailyGoalMinutes
    }

    private var dailyProgress: Double {
        min(1, Double(progressMinutes) / Double(max(1, goalMinutes)))
    }

    var body: some View {
        Button(action: action) {
            // Constant spacing between three self-sizing rows: the module has a
            // stable natural height and is centred in the header, so a longer
            // name next to it never squashes or stretches these gaps.
            VStack(spacing: rowSpacing) {
                headline
                    .foregroundStyle(accent)
                progressLine
                Text("common.minutesShort \(progressMinutes) \(goalMinutes)")
                    .font(.system(size: 11.5 * scale, weight: .semibold))
                    .foregroundStyle(accent.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("streak.accessibility.compact \(goalPeriod.title) \(progressMinutes) \(goalMinutes) \(tracker.streakDays)")
        .accessibilityHint("streak.accessibility.choosePeriod")
    }

    // The day count and its flame — or the day-one badge — read as one unit:
    // matched weights, baseline alignment, and a single tight gap keep the icon
    // from drifting away from the text beside it.
    @ViewBuilder private var headline: some View {
        if tracker.streakDays == 0 {
            HStack(alignment: .firstTextBaseline, spacing: 4 * scale) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15 * scale, weight: .bold))
                Text("streak.dayOne")
                    .font(.system(size: 15 * scale, weight: .heavy, design: .rounded))
            }
            .fixedSize()
            // The sparkle carries less visual weight than the text, so a
            // geometric centre reads as shifted right; nudge left to optically
            // centre the badge over the rail below it.
            .offset(x: -4 * scale)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 4 * scale) {
                Text(verbatim: "\(tracker.streakDays)")
                    .font(.system(size: 28 * scale, weight: .heavy, design: .rounded))
                Image(systemName: "flame.fill")
                    .font(.system(size: 17 * scale, weight: .bold))
            }
        }
    }

    // Fixed-width rail, so the fill can be sized directly without a
    // GeometryReader and stays perfectly centred under the day count.
    private var progressLine: some View {
        Capsule()
            .fill(accent.opacity(0.15))
            .frame(width: railWidth, height: 7 * scale)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: [accent.opacity(0.6), accent],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6 * scale, railWidth * dailyProgress))
                    .animation(.snappy(duration: 0.4), value: dailyProgress)
            }
    }
}

/// Themed sheet for editing the player's name, styled to match the app rather
/// than a plain system alert.
struct NameEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let theme: AnimalCharacter
    @Binding var name: String
    let onSave: () -> Void
    @FocusState private var focused: Bool
    @State private var hasRequestedInitialFocus = false

    private func save() {
        onSave()
        dismiss()
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)

            VStack(spacing: 6) {
                theme.artwork
                    .resizable()
                    .scaledToFit()
                    .frame(width: 54, height: 54)

                Text("name.whatsYourName")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(theme.deepColor)
            }

            TextField(String(), text: $name, prompt: Text("name.placeholder"))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .focused($focused)
                .textContentType(.name)
                .submitLabel(.done)
                .onSubmit(save)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(focused ? theme.color : theme.deepColor.opacity(0.15),
                                lineWidth: focused ? 2 : 1)
                )
                .animation(.snappy(duration: 0.2), value: focused)

            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Text("common.cancel")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(theme.deepColor.opacity(0.15), lineWidth: 1)
                        )
                        .foregroundStyle(theme.deepColor)
                }

                Button(action: save) {
                    Text("common.save")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            LinearGradient(colors: [theme.color, theme.deepColor],
                                           startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            // Requesting focus during the sheet's own presentation makes iOS
            // animate the sheet and keyboard in competing passes. Waiting for
            // that transition to settle gives the keyboard one smooth entry.
            guard !hasRequestedInitialFocus else { return }
            hasRequestedInitialFocus = true
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            focused = true
        }
    }
}

private enum GoalPeriod: String, CaseIterable, Identifiable {
    case daily
    case weekly

    var id: String { rawValue }
    var title: String {
        self == .daily
            ? L("goalPeriod.daily")
            : L("goalPeriod.weekly")
    }
}

struct DailyGoalPicker: View {
    let theme: AnimalCharacter
    @ObservedObject private var tracker = PlaytimeTracker.shared
    @AppStorage("ui.goalPeriod") private var goalPeriodRaw = GoalPeriod.weekly.rawValue

    private var goalPeriod: GoalPeriod { GoalPeriod(rawValue: goalPeriodRaw) ?? .weekly }
    private let goalOptions = Array(stride(from: 5, through: 60, by: 5))

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("goal.title")
                .font(.headline)
            Picker("goal.period", selection: $goalPeriodRaw) {
                ForEach(GoalPeriod.allCases) { period in
                    Text(period.title).tag(period.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Text(goalPeriod == .weekly ? "goal.promptWeekly" : "goal.promptDaily")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(goalOptions, id: \.self) { minutes in
                    Button {
                        goalPeriod == .weekly ? tracker.setWeeklyGoal(minutes) : tracker.setDailyGoal(minutes)
                    } label: {
                        Text(verbatim: "\(minutes)")
                    }
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(selectedGoalMinutes == minutes ? theme.color : .white,
                                    in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(selectedGoalMinutes == minutes ? .white : theme.deepColor)
                }
            }
        }
        .frame(width: 280)
    }

    private var selectedGoalMinutes: Int {
        goalPeriod == .weekly ? tracker.weeklyGoalMinutes : tracker.dailyGoalMinutes
    }
}

// MARK: - Level cards

enum LevelCardStatus: Equatable {
    case locked(progress: Double)  // progress toward unlocking (0–1)
    case available
    case recommended
    case completed
}

/// The folded, clipped-corner marker used for the 10–19 trophy tier.
private struct CornerFlagShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.18, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.width * 0.82, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.height * 0.18),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.54))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.91, y: rect.height * 0.66),
                          control: CGPoint(x: rect.maxX, y: rect.height * 0.61))
        path.addLine(to: CGPoint(x: rect.width * 0.23, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.height * 0.84),
                          control: CGPoint(x: rect.width * 0.03, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.height * 0.18))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.18, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// The swallowtail ribbon marker used for the 20–29 trophy tier.
private struct PennantShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.18, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.width * 0.82, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.height * 0.18),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.86))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.87, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.width * 0.58, y: rect.height * 0.74))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.height * 0.71),
                          control: CGPoint(x: rect.width * 0.54, y: rect.height * 0.71))
        path.addLine(to: CGPoint(x: rect.width * 0.13, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.height * 0.86),
                          control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.height * 0.18))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.18, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// A rounded rectangle whose path begins and ends at the top-edge centre —
/// directly behind the completed card's crown. Tracing it with `.trim`
/// (0 → 1) makes the gold border unspool from under the crown, sweep all the
/// way around, and close its seam back behind the crown, instead of starting
/// and stopping at the right edge.
private struct CrownSeamRoundedRectangle: Shape {
    var cornerRadius: CGFloat
    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, min(rect.width, rect.height) / 2)
        var path = Path()
        // Start behind the crown, at the centre of the top edge.
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        // Top edge → top-right corner
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r,
                    startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        // Right edge → bottom-right corner
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r,
                    startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        // Bottom edge → bottom-left corner
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r,
                    startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        // Left edge → top-left corner
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r,
                    startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        // Top edge back to the centre, closing the seam behind the crown.
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        return path
    }
}

/// Redesigned level card: a big central number, a trophy score line, a
/// three-dot progress indicator, and a top-left tier badge. Reaching the
/// maximum score turns the card into a celebratory gold "completed" card.
private struct HeaderTrophyIcon: View {
    let isHighlighted: Bool

    var body: some View {
        ZStack {
            Image(systemName: "trophy.fill")
                .scaleEffect(isHighlighted ? 1.34 : 1)
                .rotationEffect(.degrees(isHighlighted ? -7 : 0))
            Image(systemName: "sparkle")
                .font(.caption2.weight(.bold))
                .offset(x: 10, y: -10)
                .scaleEffect(isHighlighted ? 1 : 0.3)
                .opacity(isHighlighted ? 0.9 : 0)
        }
    }
}

private struct TrophyCountText: View {
    let from: Int
    let to: Int
    let celebrationStartedAt: Date?
    var suffix = ""
    // The score waits until the trophy's landing pulse has fully settled.
    var delay = 1.16
    var duration = 0.78

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = celebrationStartedAt.map {
                context.date.timeIntervalSince($0)
            } ?? .greatestFiniteMagnitude
            let progress = celebrationStartedAt == nil
                ? 1
                : min(1, max(0, (elapsed - delay) / duration))
            let eased = 1 - pow(1 - progress, 3)
            let value = Int((Double(from) + Double(to - from) * eased).rounded())
            Text(verbatim: "\(value)\(suffix)")
                .contentTransition(.numericText())
                .scaleEffect(1 + sin(progress * .pi) * 0.13)
        }
        .accessibilityLabel(Text(verbatim: "\(to)\(suffix)"))
    }
}

/// One trophy in flight from a level card up to the category header. All of its
/// geometry lives in the shared "home" coordinate space, so the copy starts
/// exactly overlapping the card's trophy glyph and lands exactly on the header's.
private struct FlyingTrophy: Identifiable {
    let id = UUID()
    let celebrationID: UUID
    let source: CGRect
    let destination: CGRect
    let sourcePointSize: CGFloat
    let destPointSize: CGFloat
    let arcHeight: CGFloat
    let color: Color
    let startedAt: Date
    let duration: TimeInterval
}

/// Renders the flying trophy each frame from the elapsed time, so the arc is a
/// real curved path (a plain `.position` animation would cut straight across).
private struct FlyingTrophyView: View {
    let flight: FlyingTrophy

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = max(0, context.date.timeIntervalSince(flight.startedAt))
            let t = min(1, elapsed / flight.duration)
            // Ease the along-path progress; keep the arc keyed to raw `t` so the
            // lift peaks at the midpoint of the flight.
            let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            let cx = flight.source.midX + (flight.destination.midX - flight.source.midX) * eased
            let cy = flight.source.midY + (flight.destination.midY - flight.source.midY) * eased
                - CGFloat(sin(Double(t) * .pi)) * flight.arcHeight
            let size = flight.sourcePointSize
                + (flight.destPointSize - flight.sourcePointSize) * eased
            // Merge softly into the header glyph over the last stretch.
            let fade = t > 0.88 ? max(0, 1 - (t - 0.88) / 0.12) : 1
            Image(systemName: "trophy.fill")
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(flight.color)
                .shadow(color: flight.color.opacity(0.35), radius: 3, y: 1)
                .opacity(fade)
                .position(x: cx, y: cy)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A time-driven focus outline for an improved ordinary level score. This
/// deliberately has no `@State` or `onChange`: as long as the celebration
/// exists, the current frame can always derive the correct glow intensity.
private struct LevelReturnFocusGlow: View {
    let startedAt: Date
    let cornerRadius: CGFloat
    let lineWidth: CGFloat
    let glowRadius: CGFloat
    let strokeColor: Color
    let glowColor: Color

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = max(0, context.date.timeIntervalSince(startedAt))
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(strokeColor, lineWidth: lineWidth)
                .shadow(color: glowColor.opacity(0.85), radius: glowRadius)
                .opacity(glowOpacity(at: elapsed))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func glowOpacity(at elapsed: TimeInterval) -> Double {
        if elapsed < 0.28 { return elapsed / 0.28 }
        if elapsed < 1.45 { return 1 }
        if elapsed < 1.98 { return 1 - ((elapsed - 1.45) / 0.53) }
        return 0
    }
}

struct LevelCardView: View {
    let level: LevelConfig
    let status: LevelCardStatus
    let best: Int
    /// Live trophies of a paused run for this level, shown after a divider.
    var pausedBest: Int = 0
    let helperBest: Int
    let showsHelperMarker: Bool
    let showsTrophies: Bool
    let isPaused: Bool
    var scoreCelebrationStart: Int?
    var isCelebratingNewScore = false
    /// Keeps the level card visibly outlined while the one-time score
    /// explanation is on screen. This is separate from the timed return glow:
    /// the score celebration deliberately starts only after the hint closes.
    var showsTutorialScoreFocus = false
    /// A timestamp drives the focus glow directly, so no SwiftUI change event
    /// can be coalesced or missed while the full-screen game is dismissed.
    var returnFocusStartedAt: Date?
    var maximumCount = 0
    var maximumCountCelebrationStart: Int?
    var isCelebratingMaximumCount = false
    var hasExternallyReachedFirstMax = false
    var celebrationID: UUID?
    /// iPad cards preserve the iPhone design, scaled as one component.
    var cardHeight: CGFloat = 96
    let theme: AnimalCharacter
    var onCelebrationFinished: ((UUID) -> Void)?
    let action: () -> Void
    @State private var trophyPulse = false
    @State private var maximumCountPulse = false
    @State private var maximumCountRingScale: CGFloat = 0.82
    @State private var maximumCountRingOpacity = 0.0
    @State private var highlightOpacity = 0.0
    @State private var animatedCelebrationID: UUID?
    // First-completion reveal: the gold border traces itself in and the
    // crown drops onto the card. These rest at their finished values so a
    // card that is simply already complete shows the border fully drawn.
    @State private var firstMaxBorderTrace: CGFloat = 1
    @State private var firstMaxCrownScale: CGFloat = 1
    @State private var firstMaxCrownOffset: CGFloat = 0
    @State private var firstMaxCrownTilt: Double = 0
    @State private var firstMaxGlowScale: CGFloat = 1
    @State private var firstMaxGlowOpacity = 0.0
    @State private var firstMaxReached = false
    @State private var firstMaxDecorationsScale: CGFloat = 1
    @State private var firstMaxDecorationsOpacity = 1.0
    @State private var animatedMaxCelebrationID: UUID?

    private var cardScale: CGFloat { cardHeight / 96 }
    private var isPad: Bool { AppLayout.isPad }

    // MARK: Tiers

    /// Achievement tiers, keyed off the trophy count. Their colors keep the
    /// selected character's hue, stepping from its primary color through its
    /// deep color to a darker finish as the score increases.
    private enum Tier {
        case empty          // 0 trophies
        case one            // 1–9
        case two            // 10–19
        case three          // 20–29
        case maxed          // 30 (completed)

        func color(for theme: AnimalCharacter) -> Color {
            switch self {
            case .empty:  return Color(white: 0.72)
            case .one:    return theme.color
            case .two:    return theme.deepColor
            case .three:
                return Color(red: theme.deepRGB.0 * 0.76,
                             green: theme.deepRGB.1 * 0.76,
                             blue: theme.deepRGB.2 * 0.76)
            case .maxed:  return Color(red: 0.30, green: 0.62, blue: 0.24)   // green
            }
        }

        /// How many of the three progress dots are active.
        var activeDots: Int {
            switch self {
            case .empty:          return 0
            case .one:            return 1
            case .two:            return 2
            case .three, .maxed:  return 3
            }
        }
    }

    /// Helper scores are intentionally kept separate from regular progress.
    /// When helper mode is visible, though, its score is the one the card must
    /// celebrate; otherwise a completed assisted run looked like a 0-score
    /// card with only an asterisk.
    private var visibleBest: Int {
        showsHelperMarker ? max(best, helperBest) : best
    }

    private func tier(for score: Int) -> Tier {
        if score >= ProgressStore.maximumTrophies(for: level) { return .maxed }
        switch score {
        case ..<1:    return .empty
        case 1...9:   return .one
        case 10...19: return .two
        default:      return .three
        }
    }

    /// During a first max count-up, keep presenting the old tier. The completed
    /// green palette becomes active only on the exact frame the counter reaches
    /// its maximum.
    private var hasVisuallyReachedFirstMax: Bool {
        firstMaxReached || hasExternallyReachedFirstMax
    }

    private var tier: Tier {
        if isCelebratingFirstMax && !hasVisuallyReachedFirstMax {
            return tier(for: celebrationDisplayStart)
        }
        return tier(for: visibleBest)
    }

    private var isLocked: Bool {
        if case .locked = status { return true }
        return false
    }

    private var isCompleted: Bool {
        visibleBest >= ProgressStore.maximumTrophies(for: level)
    }

    /// Crossing from a score below the goal to the goal is the authoritative
    /// first-max signal. The separate completion counter can arrive/reconcile
    /// independently, so using only that counter could leave the card waiting
    /// forever in its old grey/theme-colour state.
    private var isCrossingIntoMax: Bool {
        isCelebratingNewScore
            && celebrationDisplayStart < ProgressStore.maximumTrophies(for: level)
            && displayBest >= ProgressStore.maximumTrophies(for: level)
    }

    private var hasMaximumCelebration: Bool {
        isCelebratingMaximumCount || isCrossingIntoMax
    }

    private var showsCompletedAppearance: Bool {
        isCompleted && (!isCelebratingFirstMax || hasVisuallyReachedFirstMax)
    }

    /// The very first time a level is completed the card gains its gold
    /// border and crown — that milestone gets its own reveal animation and
    /// deliberately skips the theme-color highlight.
    private var isCelebratingFirstMax: Bool {
        isCrossingIntoMax
            || (isCelebratingMaximumCount && (maximumCountCelebrationStart ?? 0) == 0)
    }

    /// Every later completion keeps the existing badge pulse; the border is
    /// already there, so only the ×N counter and theme highlight react.
    private var isCelebratingRepeatMax: Bool {
        isCelebratingMaximumCount && (maximumCountCelebrationStart ?? 0) >= 1
    }

    /// Hue (0–360°) of the selected theme, used to keep the completed card's
    /// festive colors distinct from whichever animal theme is active.
    private var themeHue: Double {
        let (r, g, b) = theme.primaryRGB
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        guard d > 0 else { return 0 }
        let h: Double
        switch mx {
        case r: h = (g - b) / d
        case g: h = 2 + (b - r) / d
        default: h = 4 + (r - g) / d
        }
        return (h * 60).truncatingRemainder(dividingBy: 360) + (h < 0 ? 360 : 0)
    }

    /// The completed card celebrates in two colors: a `hero` (number, score,
    /// dots, ribbon) and a `metal` (crown, decorations, border, glow). Whichever
    /// festive color would clash with the active theme is swapped for a
    /// contrasting accent, guaranteeing strong contrast in every theme.
    private var completedPalette: (hero: Color, metal: Color) {
        let green = Color(red: 0.24, green: 0.60, blue: 0.28)
        let gold = Color(red: 0.87, green: 0.66, blue: 0.12)
        let violet = Color(red: 0.42, green: 0.35, blue: 0.78)
        let h = themeHue
        if (80...175).contains(h) { return (hero: violet, metal: gold) } // green theme
        return (hero: green, metal: gold)
    }

    /// Trophy counts shown in the menu, always clamped to the maximum — even
    /// when in-game round-off is off and a run pushed the raw score past 30.
    private var displayBest: Int { min(visibleBest, ProgressStore.maximumTrophies(for: level)) }
    private var displayPaused: Int { min(pausedBest, ProgressStore.maximumTrophies(for: level)) }
    private var celebrationDisplayStart: Int {
        min(scoreCelebrationStart ?? displayBest, ProgressStore.maximumTrophies(for: level))
    }
    private var levelScoreCountDelay: TimeInterval { 0.3 }
    private var levelScoreCountDuration: TimeInterval { 0.78 }

    /// `TrophyCountText` rounds each interpolated value. With the cubic easing,
    /// the final integer therefore appears before progress reaches exactly 1.
    /// Schedule the icon pulse at that real visual landing point, rather than
    /// at an unrelated fixed delay.
    private var levelScoreFinalValueOffset: TimeInterval {
        let difference = abs(displayBest - celebrationDisplayStart)
        guard difference > 0 else { return levelScoreCountDelay }
        let finalRoundingDistance = 0.5 / Double(difference)
        let progressWhenFinalValueAppears = 1 - pow(finalRoundingDistance, 1.0 / 3.0)
        return levelScoreCountDelay
            + levelScoreCountDuration * progressWhenFinalValueAppears
    }

    /// Seconds from *now* until the card's number visually lands on its new
    /// value. The trophy pulse and — on a first completion — the gold border
    /// reveal both key off this, so they always follow the count-up.
    private var scoreCountEndDelay: TimeInterval {
        returnFocusStartedAt.map {
            max(0, $0.addingTimeInterval(levelScoreFinalValueOffset).timeIntervalSinceNow)
        } ?? 0
    }
    private var helperMarker: String {
        showsHelperMarker && helperBest > best ? "*" : ""
    }

    /// A lone "1" reads right-of-centre because of its top flag, so its stem
    /// misses the middle dot; nudge just that glyph left to line them up.
    private var numberNudge: CGFloat { level.cardNumber == "1" ? -1 : 0 }

    // MARK: Body

    var body: some View {
        Button {
            AppAudio.shared.playMenuTap()
            action()
        } label: {
            Group {
                if showsCompletedAppearance {
                    completedCard
                } else {
                    standardCard
                }
            }
            .frame(height: cardHeight)
            .opacity(isLocked ? 0.55 : 1)
            .scaleEffect((status == .recommended ? 1.02 : 1) * (trophyPulse ? 1.04 : 1))
            .overlay {
                if showsTutorialScoreFocus {
                    // The tutorial hint lasts longer than the ordinary return
                    // glow, so its outline is state-driven and remains fully
                    // visible until the hint is dismissed.
                    RoundedRectangle(cornerRadius: 18 * cardScale)
                        .strokeBorder(.white.opacity(0.96), lineWidth: 7 * cardScale)
                        .overlay {
                            RoundedRectangle(cornerRadius: 18 * cardScale)
                                .strokeBorder(theme.deepColor, lineWidth: 4 * cardScale)
                        }
                        .shadow(color: theme.color.opacity(0.95), radius: 11 * cardScale)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                } else if let returnFocusStartedAt {
                    // Always identify the level the player just returned from.
                    // This stays useful when its score was already maxed: the
                    // completion border is permanent, while this themed focus
                    // glow briefly singles out the card from the other levels.
                    LevelReturnFocusGlow(
                        startedAt: returnFocusStartedAt,
                        cornerRadius: 18 * cardScale,
                        lineWidth: 4 * cardScale,
                        glowRadius: 9 * cardScale,
                        strokeColor: theme.deepColor,
                        glowColor: theme.color
                    )
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
        .onAppear {
            animateTrophyPulseIfNeeded()
            animateMaximumCountIfNeeded()
        }
        .onChange(of: isCelebratingNewScore) { _ in animateTrophyPulseIfNeeded() }
        .onChange(of: isCelebratingMaximumCount) { _ in animateMaximumCountIfNeeded() }
        .onChange(of: isCrossingIntoMax) { _ in animateMaximumCountIfNeeded() }
        .onChange(of: hasExternallyReachedFirstMax) { reached in
            guard reached, isCelebratingFirstMax else { return }
            animatedMaxCelebrationID = celebrationID
            animateFirstMaxReveal(forceImmediate: true)
        }
        // The celebration token is the authoritative trigger. Watching it as
        // well makes the outline reliable when score data and celebration
        // state arrive atomically in the same return-to-menu transaction.
        .onChange(of: celebrationID) { _ in
            animateTrophyPulseIfNeeded()
            animateMaximumCountIfNeeded()
        }
    }

    // MARK: Standard card

    private var standardCard: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 4) {
                Spacer(minLength: 2)
                Text(level.cardNumber)
                    .font(.system(size: 34 * cardScale, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(theme.deepColor)
                    .offset(x: numberNudge)
                centerLine
                Spacer(minLength: 2)
                progressDots(active: tier.activeDots, color: tier.color(for: theme))
                    .padding(.bottom, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8 * cardScale)

            tierBadge
                .padding(.top, 9 * cardScale)
                .padding(.leading, 9 * cardScale)

        }
        .background(cardFill, in: RoundedRectangle(cornerRadius: 18 * cardScale))
        .overlay(
            RoundedRectangle(cornerRadius: 18 * cardScale)
                .stroke(borderColor, lineWidth: (status == .recommended ? 2.5 : 1) * cardScale)
        )
        .shadow(color: .black.opacity(0.06), radius: 5, x: 0, y: 3)
    }

    private var cardFill: Color {
        visibleBest == 0 ? Color.white.opacity(0.6) : .white
    }

    private var borderColor: Color {
        if status == .recommended { return theme.color }
        return visibleBest == 0 ? Color(white: 0.85) : tier.color(for: theme).opacity(0.35)
    }

    // MARK: Center score line

    @ViewBuilder
    private var centerLine: some View {
        if status == .recommended && visibleBest == 0 && !isPaused {
            Text("menu.startHere")
                .font(.system(size: 10 * cardScale * 1.2, weight: .bold))
                .foregroundStyle(theme.deepColor)
        } else if !showsTrophies {
            if isPaused {
                Image(systemName: "pause.fill")
                    .font(.system(size: 10 * cardScale, weight: .bold))
                    .foregroundStyle(theme.deepColor.opacity(0.75))
            }
        } else if isPaused {
            // Measure both rows at their natural width. Without `fixedSize`,
            // SwiftUI can report the regular row as fitting only after it has
            // already shortened the trophy count to an ellipsis.
            ViewThatFits(in: .horizontal) {
                pausedScoreLine(isCompact: false)
                    .fixedSize(horizontal: true, vertical: false)
                pausedScoreLine(isCompact: true)
                    .fixedSize(horizontal: true, vertical: false)
            }
        } else {
            trophyChip(reportsAnchor: true)
        }
    }

    private func pausedScoreLine(isCompact: Bool) -> some View {
        let contentScale: CGFloat = isCompact ? 0.88 : 1
        return HStack(spacing: (isCompact ? 2 : 4) * cardScale) {
            trophyChip(contentScale: contentScale, reportsAnchor: !isCompact)
            Rectangle()
                .fill(theme.deepColor.opacity(0.25))
                .frame(width: 1, height: 11 * cardScale * contentScale)
            HStack(spacing: (isCompact ? 1 : 2) * cardScale) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 8 * cardScale * contentScale))
                Text(verbatim: "\(displayPaused)")
                    .font(.system(size: 11 * cardScale * contentScale, weight: .bold))
            }
            .foregroundStyle(theme.deepColor.opacity(0.7))
        }
    }

    private func trophyChip(contentScale: CGFloat = 1, reportsAnchor: Bool = false) -> some View {
        HStack(spacing: (contentScale < 1 ? 1 : 3) * cardScale) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 9 * cardScale * contentScale))
                // The launch anchor is reported from the unscaled layout frame
                // (scaleEffect is a render transform, so the pulse never moves
                // it) so the flying trophy starts exactly overlapping this glyph.
                .background { if reportsAnchor { Color.clear.reportCardTrophy(level.id) } }
                .scaleEffect(trophyPulse ? 1.48 : 1)
                .rotationEffect(.degrees(trophyPulse ? -12 : 0))
            TrophyCountText(from: celebrationDisplayStart,
                             to: displayBest,
                             celebrationStartedAt: isCelebratingNewScore
                                 ? returnFocusStartedAt : nil,
                             suffix: helperMarker,
                             delay: levelScoreCountDelay,
                             duration: levelScoreCountDuration)
                .font(.system(size: 12 * cardScale * contentScale, weight: .bold))
        }
        .foregroundStyle(tier == .empty ? Color(white: 0.6) : tier.color(for: theme))
    }

    private func animateTrophyPulseIfNeeded() {
        guard isCelebratingNewScore else {
            trophyPulse = false
            highlightOpacity = 0
            animatedCelebrationID = nil
            return
        }
        guard let celebrationID, animatedCelebrationID != celebrationID else { return }
        animatedCelebrationID = celebrationID

        // The pulse fires at the moment the number visually reaches its new
        // value — for ordinary and (now that they count up) completed cards
        // alike, so the little kick always lands on the final trophy. (The
        // theme highlight overlay is driven from `animateRepeatMaxPulse`, the
        // only place it is actually rendered.)
        let pulseDelay = scoreCountEndDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + pulseDelay) {
            guard self.celebrationID == celebrationID,
                  isCelebratingNewScore else { return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.54)) {
                trophyPulse = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + pulseDelay + 0.62) {
            guard self.celebrationID == celebrationID else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.7)) {
                trophyPulse = false
            }
        }
        if !hasMaximumCelebration {
            DispatchQueue.main.asyncAfter(deadline: .now() + pulseDelay + 0.72) {
                guard self.celebrationID == celebrationID else { return }
                onCelebrationFinished?(celebrationID)
            }
        }
    }

    private func animateMaximumCountIfNeeded() {
        guard hasMaximumCelebration else {
            maximumCountPulse = false
            maximumCountRingOpacity = 0
            firstMaxBorderTrace = 1
            firstMaxCrownScale = 1
            firstMaxCrownOffset = 0
            firstMaxCrownTilt = 0
            firstMaxGlowScale = 1
            firstMaxGlowOpacity = 0
            firstMaxReached = false
            firstMaxDecorationsScale = 1
            firstMaxDecorationsOpacity = 1
            animatedMaxCelebrationID = nil
            return
        }
        // Run the reveal or pulse exactly once per celebration, even if the
        // grid re-renders and re-appears mid-animation.
        guard let celebrationID, animatedMaxCelebrationID != celebrationID else { return }
        animatedMaxCelebrationID = celebrationID
        if isCelebratingFirstMax {
            animateFirstMaxReveal(forceImmediate: hasExternallyReachedFirstMax)
        } else {
            animateRepeatMaxPulse()
        }
    }

    /// First completion: the crown drops in first, then the gold border
    /// unspools from behind it, sweeps around the card, and closes its seam
    /// back behind the crown while a soft metal flash blooms outward. Timed to
    /// finish well inside the celebration's own lifetime so it never lingers or
    /// blocks the eye.
    private func animateFirstMaxReveal(forceImmediate: Bool = false) {
        // Hold the border and crown hidden from the first frame: the card first
        // counts its number up to the maximum, and only then does the festive
        // edge reveal itself — matching "the outline begins once the count
        // reaches max".
        maximumCountPulse = false
        maximumCountRingOpacity = 0
        firstMaxBorderTrace = 0
        firstMaxCrownScale = 0
        firstMaxCrownOffset = -12
        firstMaxCrownTilt = 0
        firstMaxGlowScale = 0.9
        firstMaxGlowOpacity = 0
        firstMaxReached = false
        firstMaxDecorationsScale = 0.78
        firstMaxDecorationsOpacity = 0

        let celebrationID = self.celebrationID
        let revealDelay = forceImmediate ? 0 : scoreCountEndDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + revealDelay) {
            guard self.celebrationID == celebrationID,
                  isCelebratingFirstMax else { return }

            // Reaching max is one coherent beat: the palette turns green, the
            // side decorations appear, the crown lands and the outline begins.
            withTransaction(Transaction(animation: nil)) {
                firstMaxReached = true
            }
            // Give SwiftUI one commit to replace the standard card with the
            // completed hierarchy. Its hidden decoration states then animate
            // visibly instead of being inserted at their final values.
            DispatchQueue.main.async {
                guard self.celebrationID == celebrationID else { return }
                withAnimation(.spring(response: 0.48, dampingFraction: 0.62)) {
                    firstMaxDecorationsScale = 1
                    firstMaxDecorationsOpacity = 1
                }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.52)) {
                    firstMaxCrownScale = 1
                    firstMaxCrownOffset = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.42)) {
                        firstMaxCrownTilt = -6
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                        firstMaxCrownTilt = 0
                    }
                }
            }

            // 2. Once the crown has landed, the border traces out from under it
            //    and the metal flash blooms along with it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                firstMaxGlowScale = 0.9
                firstMaxGlowOpacity = 0.7
                withAnimation(.easeInOut(duration: 0.62)) { firstMaxBorderTrace = 1 }
                withAnimation(.easeOut(duration: 0.75)) {
                    firstMaxGlowScale = 1.3
                    firstMaxGlowOpacity = 0
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.12) {
                guard self.celebrationID == celebrationID,
                      let celebrationID else { return }
                onCelebrationFinished?(celebrationID)
            }
        }
    }

    /// Every later completion: the border already exists, so only the ×N badge
    /// pulses and the theme highlight breathes — unchanged from before.
    private func animateRepeatMaxPulse() {
        firstMaxBorderTrace = 1
        firstMaxCrownScale = 1
        firstMaxCrownOffset = 0
        firstMaxCrownTilt = 0
        firstMaxGlowOpacity = 0

        withAnimation(.easeOut(duration: 0.38)) { highlightOpacity = 1 }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.58)) { maximumCountPulse = true }
        maximumCountRingScale = 0.82
        maximumCountRingOpacity = 0.78
        withAnimation(.easeOut(duration: 0.78)) {
            maximumCountRingScale = 1.46
            maximumCountRingOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.92) {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) { maximumCountPulse = false }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.62) {
            withAnimation(.easeOut(duration: 0.42)) { highlightOpacity = 0.32 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.98) {
            withAnimation(.easeOut(duration: 0.2)) { highlightOpacity = 0 }
        }
        if let celebrationID {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                guard animatedMaxCelebrationID == celebrationID else { return }
                onCelebrationFinished?(celebrationID)
            }
        }
    }

    // MARK: Tier badge (top-left)

    @ViewBuilder
    private var tierBadge: some View {
        switch tier {
        case .empty:
            // No score yet: leave the corner empty.
            EmptyView()
        case .one:
            RoundedRectangle(cornerRadius: 1.5)
                .fill(tier.color(for: theme))
                .frame(width: 9 * cardScale, height: 9 * cardScale)
                .rotationEffect(.degrees(45))
                .padding(.leading, 1)
        case .two:
            cornerFlag
        case .three, .maxed:
            pennant
        }
    }

    /// A clipped corner flag for the middle achievement tier (10–19).
    private var cornerFlag: some View {
        CornerFlagShape()
            .fill(tier.color(for: theme))
            .frame(width: 12 * cardScale, height: 14 * cardScale)
    }

    /// A notched ribbon for the highest non-complete tier (20–29).
    private var pennant: some View {
        PennantShape()
            .fill(tier.color(for: theme))
            .frame(width: 12 * cardScale, height: 14 * cardScale)
    }

    // MARK: Progress dots

    private func progressDots(active: Int, color: Color) -> some View {
        HStack(spacing: 6 * cardScale) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(index < active ? color : Color(white: 0.85))
                    .frame(width: 6 * cardScale, height: 6 * cardScale)
            }
        }
    }

    // MARK: Completed (max-score) card

    private var completedCard: some View {
        let hero = completedPalette.hero
        let metal = completedPalette.metal
        return ZStack {
            VStack(spacing: 3) {
                Spacer(minLength: 8)
                Text(level.cardNumber)
                    .font(.system(size: 34 * cardScale, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(hero)
                    .offset(x: numberNudge)
                HStack(spacing: 4 * cardScale) {
                    HStack(spacing: 3) {
                        Image(systemName: "trophy.fill").font(.system(size: 9 * cardScale))
                            .background { Color.clear.reportCardTrophy(level.id) }
                            .scaleEffect(trophyPulse ? 1.48 : 1)
                            .rotationEffect(.degrees(trophyPulse ? -12 : 0))
                        // When a returning run crosses into the maximum the number
                        // counts up old→max first; the gold border and crown only
                        // reveal once it lands (see `animateFirstMaxReveal`).
                        if isCelebratingNewScore {
                            TrophyCountText(from: celebrationDisplayStart,
                                             to: displayBest,
                                             celebrationStartedAt: returnFocusStartedAt,
                                             suffix: helperMarker,
                                             delay: levelScoreCountDelay,
                                             duration: levelScoreCountDuration)
                                .font(.system(size: 12 * cardScale, weight: .bold))
                        } else {
                            Text(verbatim: "\(displayBest)\(helperMarker)")
                                .font(.system(size: 12 * cardScale, weight: .bold))
                        }
                    }
                    .foregroundStyle(hero)
                    // The repeat-max marker is a superscript detail, not a
                    // second item in the centred trophy-score layout. It only
                    // appears from the *second* completion onward (×2, ×3, …);
                    // the first completion is marked by the border and crown.
                    .overlay(alignment: .topTrailing) {
                        if maximumCount >= 2 {
                            maximumCountBadge(fill: hero, metal: metal)
                                // The wrapper is only an alignment column; the
                                // visible outline keeps its natural width.
                                .frame(width: 23 * cardScale, alignment: .leading)
                                // Jens: adjust this x-value to fine-tune the
                                // repeat-max badge's horizontal placement.
                                .offset(x: 20 * cardScale, y: -7 * cardScale)
                        }
                    }

                    if isPaused {
                        Rectangle()
                            .fill(theme.deepColor.opacity(0.25))
                            .frame(width: 1, height: 11 * cardScale)
                        HStack(spacing: 2 * cardScale) {
                            Image(systemName: "pause.fill").font(.system(size: 8 * cardScale))
                            Text(verbatim: "\(displayPaused)")
                                .font(.system(size: 11 * cardScale, weight: .bold))
                        }
                        // A paused run is live progress, never a max badge.
                        .foregroundStyle(theme.deepColor)
                    }
                }
                Spacer(minLength: 2)
                progressDots(active: 3, color: hero)
                    .padding(.bottom, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8 * cardScale)

            // Laurel branches flanking the number.
            HStack {
                Image(systemName: "laurel.leading")
                Spacer()
                Image(systemName: "laurel.trailing")
            }
            .font(.system(size: 30 * cardScale, weight: .regular))
            .foregroundStyle(metal.opacity(0.55))
            .scaleEffect(firstMaxDecorationsScale)
            .opacity(firstMaxDecorationsOpacity)
            // Jens: iPad cards are wider but also much taller; pull the
            // laurels inward there so they do not cling to the outer edge.
            .padding(.horizontal, isPad ? 15 * cardScale : 3)

            // Subtle sparkle accents.
            Image(systemName: "sparkle")
                .font(.system(size: 8))
                .foregroundStyle(metal)
                .offset(x: 31, y: -20)
            Image(systemName: "sparkle")
                .font(.system(size: 6))
                .foregroundStyle(metal.opacity(0.8))
                .offset(x: -33, y: 22)

        }
        .background(
            RoundedRectangle(cornerRadius: 18 * cardScale)
                .fill(Color(red: 1.0, green: 0.99, blue: 0.93))
        )
        // Repeat-max theme highlight sits *behind* the gold border so the
        // festive edge always stays crisp on top of the colored glow.
        .overlay {
            if isCelebratingRepeatMax {
                RoundedRectangle(cornerRadius: 18 * cardScale)
                    .stroke(theme.deepColor, lineWidth: 4 * cardScale)
                    .shadow(color: theme.color.opacity(0.85), radius: 9 * cardScale)
                    .opacity(highlightOpacity)
                    .allowsHitTesting(false)
            }
        }
        // The gold border. On a first completion it traces itself in from
        // behind the crown (firstMaxBorderTrace 0→1), wraps around, and closes
        // its seam back behind the crown; otherwise it rests fully drawn.
        .overlay(
            CrownSeamRoundedRectangle(cornerRadius: 18 * cardScale)
                .trim(from: 0, to: effectiveFirstMaxBorderTrace)
                .stroke(metal, lineWidth: 2 * cardScale)
        )
        // A soft metal flash that blooms outward as the border first appears.
        .overlay {
            RoundedRectangle(cornerRadius: 18 * cardScale)
                .stroke(metal, lineWidth: 2.5 * cardScale)
                .scaleEffect(firstMaxGlowScale)
                .opacity(firstMaxGlowOpacity)
                .allowsHitTesting(false)
        }
        .shadow(color: metal.opacity(0.45), radius: 8 * cardScale)
        .overlay(alignment: .top) {
            completedRibbon(fill: hero, crown: metal)
                .scaleEffect(effectiveFirstMaxCrownScale, anchor: .bottom)
                .rotationEffect(.degrees(firstMaxCrownTilt))
                .offset(y: -9 + effectiveFirstMaxCrownOffset)
        }
    }

    /// While a first-completion card is counting its number up, its border and
    /// crown must stay hidden even on the very first frame — before the reveal
    /// animation has had a chance to run. Once the reveal owns this celebration
    /// (`animatedMaxCelebrationID == celebrationID`) the live values take over.
    private var isPendingFirstMaxReveal: Bool {
        isCelebratingFirstMax && animatedMaxCelebrationID != celebrationID
    }
    private var effectiveFirstMaxBorderTrace: CGFloat {
        isPendingFirstMaxReveal ? 0 : firstMaxBorderTrace
    }
    private var effectiveFirstMaxCrownScale: CGFloat {
        isPendingFirstMaxReveal ? 0 : firstMaxCrownScale
    }
    private var effectiveFirstMaxCrownOffset: CGFloat {
        isPendingFirstMaxReveal ? -12 : firstMaxCrownOffset
    }

    /// Small ribbon with a crown that overlaps the top of the card. The ribbon
    /// takes the hero color and the crown the contrasting metal color.
    private func completedRibbon(fill: Color, crown: Color) -> some View {
        Image(systemName: "crown.fill")
            // Scale with the completed card on iPad; iPhone stays at 11pt.
            .font(.system(size: 11 * cardScale, weight: .bold))
            .foregroundStyle(crown)
            .padding(.horizontal, 11 * cardScale)
            .padding(.vertical, 4 * cardScale)
            .background(
                RoundedRectangle(cornerRadius: 6 * cardScale)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6 * cardScale)
                    .stroke(.white.opacity(0.6), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
    }

    private func maximumCountBadge(fill: Color, metal: Color) -> some View {
        let cornerRadius = 3.5 * cardScale
        return Text(maximumCount >= ProgressStore.maximumCompletionCount ? L("menu.maximumCount") : "×\(maximumCount)")
            // Deliberately smaller than the trophy number: the airy outline,
            // rather than the text, is the badge's visual footprint.
            .font(.system(size: 5.6 * cardScale, weight: .heavy, design: .rounded))
            .foregroundStyle(fill)
            .padding(.horizontal, 1.5 * cardScale)
            .padding(.vertical, 1 * cardScale)
            .background(.white.opacity(0.5), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(metal.opacity(0.8), lineWidth: 1 * cardScale)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(metal, lineWidth: 1.2 * cardScale)
                    .scaleEffect(maximumCountRingScale)
                    .opacity(maximumCountRingOpacity)
            }
            .shadow(color: metal.opacity(0.18), radius: 2, y: 1)
            .scaleEffect(maximumCountPulse ? 1.18 : 1, anchor: .center)
            .accessibilityLabel(maximumCount >= ProgressStore.maximumCompletionCount
                ? L("menu.maximumCount") : L("menu.maximumCount.accessibility \(maximumCount)"))
    }
}

// MARK: - Game cover

extension View {
    /// Full screen on iOS; falls back to a sheet on macOS,
    /// where fullScreenCover is unavailable.
    @ViewBuilder
    func gameCover(item: Binding<LevelSelection?>, onDismiss: @escaping () -> Void) -> some View {
#if os(macOS)
        sheet(item: item, onDismiss: onDismiss) { selection in
            GameView(level: selection.level)
                .frame(minWidth: 420, minHeight: 720)
                .gameEnvironment()
        }
#else
        fullScreenCover(item: item, onDismiss: onDismiss) { selection in
            GameView(level: selection.level)
                .gameEnvironment()
        }
#endif
    }
}

#Preview {
    ContentView()
}
