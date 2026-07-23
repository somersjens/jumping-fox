//
//  ContentView.swift
//  Jumping Fox
//
//  Home screen: playtime progress, cyclic category selector with
//  arrow navigation (plus optional swipe), and redesigned level
//  cards with a big central number.
//

import SwiftUI
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
    let id = UUID()
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
    @State private var selection: LevelSelection?
    @State private var showPremium = false
    @State private var showGoalPicker = false
    @State private var showNameEditor = false
    @State private var nameDraft = ""
    @State private var refreshID = UUID()
    @State private var showsOptions = false
    @State private var expandedOptionInfo: String?
    @State private var headerDetailsHeight: CGFloat = 0
    @State private var lastOpenedLevelID: String?
    @State private var openedLevelScore = 0
    @State private var openedLevelMaximumCount = 0
    @State private var openedCategoryTrophies = 0
    @State private var openedTotalTrophies = 0
    @State private var scoreCelebration: ScoreCelebration?
    @State private var highlightsHeaderTrophies = false
    @State private var showTutorialScoreHint = false
    @State private var scoreHintLevelID: String?
    @State private var suppressCharacterTap = false
    @State private var maximumCountPreview: Int?
    @State private var maximumCountPreviewLevelID: String?
    @State private var secondMaximumCountPreview: Int?
    @State private var secondMaximumCountPreviewLevelID: String?
    @State private var secondScorePreview: Int?
    @State private var secondScorePreviewLevelID: String?

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
    private var levelGridSpacing: CGFloat { isPad ? 18 : 12 }
    /// On iPad, give the menu's stacked control rows just enough separation
    /// to match their larger controls without turning the header into a list.
    private var menuCardSectionSpacing: CGFloat { isPad ? 18 : 14 }
    private var menuControlSpacing: CGFloat { isPad ? 16 : 11 }

    var body: some View {
        // Read the revision so an iCloud update redraws all score cards.
        let _ = progress.revision
        ZStack {
            LinearGradient(
                colors: [character.skyColor, character.tintColor],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: isPad ? 26 : 18) {
                    menuCard.opacity(showTutorialScoreHint ? 0.30 : 1)
                    levelGrid
                }
                .padding(isPad ? 32 : 16)
                .frame(maxWidth: isPad ? 900 : 720)
                .frame(maxWidth: .infinity)
                .id(refreshID)
            }
        }
        .sheet(isPresented: $showPremium) {
            PremiumView()
                .premiumSheetPresentation()
        }
        .popover(isPresented: $showGoalPicker, arrowEdge: .top) {
            DailyGoalPicker(theme: character)
                .padding()
                .presentationCompactAdaptation(.popover)
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
            let shouldShowTutorialHint = tutorial.shouldShowScoreHint
            if shouldShowTutorialHint, let levelID = lastOpenedLevelID {
                scoreHintLevelID = levelID
                withAnimation(.easeOut(duration: 0.25)) { showTutorialScoreHint = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
                    withAnimation(.easeOut(duration: 0.2)) { showTutorialScoreHint = false }
                    scoreHintLevelID = nil
                    tutorial.consumeScoreHint()
                }
            }

            guard let levelID = lastOpenedLevelID else {
                refreshID = UUID()
                return
            }

            let newScore = displayedScore(forLevelID: levelID)
            let newMaximumCount = displayedMaximumCount(forLevelID: levelID)
            guard newScore > openedLevelScore || newMaximumCount > openedLevelMaximumCount else {
                refreshID = UUID()
                return
            }

            let celebration = ScoreCelebration(levelID: levelID,
                                               levelStart: openedLevelScore,
                                               maximumCountStart: openedLevelMaximumCount,
                                               categoryStart: openedCategoryTrophies,
                                               totalStart: openedTotalTrophies)
            // Apply the menu refresh and animation marker together. Otherwise
            // SwiftUI can paint the new total for one frame before it knows to
            // count up from the old one.
            withAnimation(.easeOut(duration: 0.34)) {
                scoreCelebration = celebration
                refreshID = UUID()
            }
            // The reward first lands on its level. Then this small cue guides
            // attention up to the category and overall progress.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.16) {
                guard scoreCelebration?.id == celebration.id else { return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.56)) {
                    highlightsHeaderTrophies = true
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.82) {
                guard scoreCelebration?.id == celebration.id else { return }
                withAnimation(.easeOut(duration: 0.24)) { highlightsHeaderTrophies = false }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                guard scoreCelebration?.id == celebration.id else { return }
                withAnimation(.easeOut(duration: 0.25)) { scoreCelebration = nil }
            }
        })
        .onChange(of: selection?.id) { selectionID in
            guard let selectionID else { return }
            lastOpenedLevelID = selectionID
            openedLevelScore = displayedScore(forLevelID: selectionID)
            openedLevelMaximumCount = displayedMaximumCount(forLevelID: selectionID)
            openedCategoryTrophies = categoryTrophies
            openedTotalTrophies = totalTrophies
        }
        .task {
            premium.startInitialRefresh()
        }
        .overlay {
            if showTutorialScoreHint {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.06).ignoresSafeArea()
                    Text("tutorial.scoreHint")
                        .font(.headline.weight(.heavy))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(character.deepColor.opacity(0.96), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.9), lineWidth: 2))
                        .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
                        .padding(.horizontal, 22)
                        .padding(.top, 112)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) { showTutorialScoreHint = false }
                    scoreHintLevelID = nil
                    tutorial.consumeScoreHint()
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

    // MARK: Combined top menu

    private var menuCard: some View {
        VStack(spacing: menuCardSectionSpacing) {
            HStack(alignment: .center, spacing: 12) {
                Button {
                    // A long press may also end as a button tap; consume that
                    // trailing action instead of opening the premium sheet.
                    guard !suppressCharacterTap else {
                        suppressCharacterTap = false
                        return
                    }
                    showPremium = true
                } label: {
                    character.artwork
                        .resizable()
                        .scaledToFill()
                        .frame(width: isPad ? 118 : 68, height: isPad ? 118 : 68)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(.white.opacity(0.9), lineWidth: 2)
                        }
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
                        TrophyCountText(from: scoreCelebration?.totalStart ?? totalTrophies,
                                         to: totalTrophies,
                                         celebrationID: scoreCelebration?.id,
                                         suffix: answerHelper ? " *" : "",
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
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: HeaderDetailsHeightKey.self, value: proxy.size.height)
                    }
                }

                Spacer(minLength: 8)

                // Streak lives to the right, capped to about a third of the row.
                CompactStreakView(accent: character.deepColor) {
                    showGoalPicker = true
                }
                .frame(width: isPad ? 142 : 106, height: headerDetailsHeight > 0 ? headerDetailsHeight : nil)
                // The right-aligned progress line has a little more visual
                // weight than the left side of this compact cluster.
                .offset(x: -4)
            }
            .onPreferenceChange(HeaderDetailsHeightKey.self) { headerDetailsHeight = $0 }

            Divider().overlay(character.deepColor.opacity(0.22))

            VStack(spacing: menuControlSpacing) {
                HStack(alignment: .center) {
                    Text(selectedFilter.title)
                    .font(.system(size: isPad ? 30 : 20, weight: .heavy, design: .rounded))
                    Label {
                        TrophyCountText(from: scoreCelebration?.categoryStart ?? categoryTrophies,
                                         to: categoryTrophies,
                                         celebrationID: scoreCelebration?.id,
                                         suffix: answerHelper ? " *" : "",
                                         duration: 0.95)
                    } icon: {
                        HeaderTrophyIcon(isHighlighted: highlightsHeaderTrophies)
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
        .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.9), lineWidth: 1)
        }
        .shadow(color: character.deepColor.opacity(0.12), radius: 14, y: 7)
    }

    private func menuFilterButton(_ filter: MenuFilter) -> some View {
        let isSelected = filter == selectedFilter
        return Button {
            if filter != .mixed || !isSelected { clearMaximumCountPreview() }
            withAnimation(.snappy(duration: 0.2)) { menuFilterRaw = filter.rawValue }
        } label: {
            menuFilterIcon(filter, isSelected: isSelected)
            .frame(maxWidth: .infinity)
            .frame(height: isPad ? 78 : 44 * menuScale)
            .background(isSelected ? character.deepColor : .white.opacity(0.7), in: Circle())
            .overlay(Circle().stroke(character.deepColor.opacity(isSelected ? 0 : 0.25), lineWidth: 1))
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

    /// The circular topic controls deliberately touch the same outer edges as
    /// the Standard/Mix picker. A regular flexible HStack centres its first
    /// and last circles inside their slots on wide screens, which made the
    /// two rows look misaligned in landscape.
    private var filterPicker: some View {
        HStack(spacing: 0) {
            ForEach(Array(MenuFilter.allCases.enumerated()), id: \.element.id) { index, filter in
                menuFilterButton(filter)
                    .frame(width: isPad ? 78 : 44, height: isPad ? 78 : 44)

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

    private var totalTrophies: Int {
        LevelCatalog.byCategory.values.flatMap { $0 }
            .filter { !$0.requiresPremium }
            .reduce(0) { $0 + trophies(for: $1) }
    }

    private var categoryTrophies: Int {
        LevelCatalog.levels(for: category)
            .filter { !$0.requiresPremium }
            .reduce(0) { $0 + trophies(for: $1) }
    }

    /// Trophies earned for a base level, counting all three of its practice-mode
    /// variants and any in-progress paused run — whichever is highest. This is
    /// why a paused (or Random/Mixed) level still adds to the category and grand
    /// totals.
    private func trophies(for level: LevelConfig) -> Int {
        // Each mode variant is scored and capped against its own goal (Order 20,
        // Random 30, Mixed 40), so the best across them is compared like-for-like.
        level.allModeVariants.map { variant in
            let recorded = ProgressStore.bestScore(levelID: variant.id, helperEnabled: answerHelper)
            let pausedRaw = PausedGameStore.shared.pausedScore(forLevelID: variant.id, includingHelper: answerHelper)
            let paused = capsTrophiesAtThirty
                ? min(ProgressStore.maximumTrophies(for: variant), pausedRaw)
                : pausedRaw
            return max(recorded, paused)
        }.max() ?? 0
    }

    /// Matches the score a level card presents in the current helper mode, so
    /// a highlight always corresponds to a visibly improved score.
    private func displayedScore(forLevelID levelID: String) -> Int {
        ProgressStore.bestScore(levelID: levelID, helperEnabled: answerHelper)
    }

    private func displayedMaximumCount(forLevelID levelID: String) -> Int {
        ProgressStore.maxCompletionCount(levelID: levelID, helperEnabled: answerHelper)
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
        guard scoreCelebration?.levelID == level.id else { return false }
        if secondScorePreviewLevelID == level.id, let secondScorePreview {
            return secondScorePreview > (scoreCelebration?.levelStart ?? 0)
        }
        return displayedScore(forLevelID: level.id) > (scoreCelebration?.levelStart ?? 0)
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
    }

    private func showMaximumCountPreview(levelID: String, count: Int) {
        maximumCountPreview = count
        let celebration = ScoreCelebration(levelID: levelID,
                                           levelStart: displayedScore(forLevelID: levelID),
                                           maximumCountStart: count - 1,
                                           categoryStart: categoryTrophies,
                                           totalStart: totalTrophies)
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
                                           totalStart: totalTrophies)
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
    }

    private var menuModePicker: some View {
        // Three equal-width buttons: Reeks · Hussel · Gemixt (Order · Random ·
        // Mixed). The label keeps one line and shrinks to fit, so a longer word
        // in another language still fits three-across without changing the base
        // text size the shorter labels use.
        HStack(spacing: 8) {
            ForEach(PracticeMode.allCases) { mode in
                let isSelected = menuMode == mode
                Button {
                    clearMaximumCountPreview()
                    withAnimation(.snappy(duration: 0.2)) {
                        menuModeRaw = mode.rawValue
                    }
                } label: {
                    Text(mode.title)
                        .font(.system(size: isPad ? 22 : 15, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(isSelected ? .white : character.deepColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: isPad ? 76 : 42)
                        .padding(.horizontal, 2)
                        .background(isSelected ? character.deepColor : .white.opacity(0.62), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(character.deepColor.opacity(isSelected ? 0 : 0.28), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("menu.accessibility.chooseMode \(mode.title)")
            }
        }
    }

    /// The Supermix filter's four buttons, each a self-contained 99-level
    /// category that combines progressively more operations.
    private var supermixCategoryPicker: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(ChallengeCategory.supermixMenu) { menuCategory in
                let isSelected = supermixCategory == menuCategory
                Button {
                    clearMaximumCountPreview()
                    withAnimation(.snappy(duration: 0.2)) {
                        supermixCategoryRaw = menuCategory.rawValue
                    }
                } label: {
                    supermixLabel(menuCategory)
                        .foregroundStyle(isSelected ? .white : character.deepColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .frame(height: isPad ? 76 : 42)
                        .background(isSelected ? character.deepColor : .white.opacity(0.62), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(character.deepColor.opacity(isSelected ? 0 : 0.28), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("menu.accessibility.chooseMode \(menuCategory.symbol)")
            }
        }
    }

    /// The "%" glyph reads visually heavier than +, −, × and ÷ at the same
    /// point size, so it renders a size smaller to match.
    private func supermixLabel(_ category: ChallengeCategory) -> Text {
        let font = Font.system(size: isPad ? 26 : 19, weight: .bold)
        guard category.symbol.hasSuffix("%") else {
            return Text(category.symbol).font(font)
        }
        let percentFont = Font.system(size: isPad ? 22 : 16, weight: .bold)
        let base = String(category.symbol.dropLast())
        return Text(base).font(font) + Text("%").font(percentFont)
    }

    private var helperModeRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.28)) {
                    showsOptions.toggle()
                }
            } label: {
                HStack {
                    Label("menu.options", systemImage: "slider.horizontal.3")
                        .font(.system(size: isPad ? 22 : 15, weight: .bold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: isPad ? 22 : 15, weight: .bold))
                        .rotationEffect(.degrees(showsOptions ? 90 : 0))
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
            ProgressStore.bestScore(levelID: $0.id, helperEnabled: true) > 0
        }
        let recommendedID = hasProgress ? nil : regular.first?.id

        return VStack(alignment: .leading, spacing: 14) {
            AdaptiveLevelGrid(spacing: levelGridSpacing,
                              minimumCardWidth: isPad ? 180 : 104,
                              maximumColumns: isPad ? 3 : .max,
                              cardHeight: levelCardHeight) {
                ForEach(regular) { level in
                    let normalBest = displayedBest(for: level,
                                                    best: ProgressStore.bestScore(levelID: level.id))
                    LevelCardView(level: level,
                                  status: status(for: level, recommendedID: recommendedID),
                                  best: normalBest,
                                  pausedBest: PausedGameStore.shared.pausedScore(forLevelID: level.id, includingHelper: answerHelper),
                                  helperBest: ProgressStore.helperOnlyBestScore(levelID: level.id),
                                  showsHelperMarker: answerHelper,
                                  showsTrophies: true,
                                  isPaused: PausedGameStore.shared.hasPausedSession(for: level, mode: lifeMode),
                                  scoreCelebrationStart: scoreCelebration?.levelID == level.id
                                      ? scoreCelebration?.levelStart : nil,
                                  isCelebratingNewScore: isCelebratingScore(for: level),
                                  maximumCount: maximumCount(for: level),
                                  maximumCountCelebrationStart: scoreCelebration?.levelID == level.id
                                      ? scoreCelebration?.maximumCountStart : nil,
                                  isCelebratingMaximumCount: scoreCelebration?.levelID == level.id
                                      && maximumCount(for: level) > (scoreCelebration?.maximumCountStart ?? 0),
                                  celebrationID: scoreCelebration?.id,
                                  cardHeight: levelCardHeight,
                                  theme: character) {
                        selection = LevelSelection(level: level)
                        clearMaximumCountPreview()
                    }
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
        if ProgressStore.isCompleted(level) {
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
                        let normalBest = displayedBest(for: level,
                                                        best: ProgressStore.bestScore(levelID: level.id))
                        LevelCardView(level: level,
                                      status: status(for: level, recommendedID: nil),
                                      best: normalBest,
                                      pausedBest: PausedGameStore.shared.pausedScore(forLevelID: level.id, includingHelper: answerHelper),
                                      helperBest: ProgressStore.helperOnlyBestScore(levelID: level.id),
                                      showsHelperMarker: answerHelper,
                                      showsTrophies: true,
                                      isPaused: PausedGameStore.shared.hasPausedSession(for: level, mode: lifeMode),
                                      scoreCelebrationStart: scoreCelebration?.levelID == level.id
                                          ? scoreCelebration?.levelStart : nil,
                                      isCelebratingNewScore: isCelebratingScore(for: level),
                                      maximumCount: maximumCount(for: level),
                                      maximumCountCelebrationStart: scoreCelebration?.levelID == level.id
                                          ? scoreCelebration?.maximumCountStart : nil,
                                      isCelebratingMaximumCount: scoreCelebration?.levelID == level.id
                                          && maximumCount(for: level) > (scoreCelebration?.maximumCountStart ?? 0),
                                      celebrationID: scoreCelebration?.id,
                                      cardHeight: levelCardHeight,
                                      theme: character) {
                            selection = LevelSelection(level: level)
                            clearMaximumCountPreview()
                        }
                    }
                }
            }
        } else {
            Button {
                showPremium = true
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
                    Image(systemName: "chevron.right")
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

private struct HeaderDetailsHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
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

                Image(systemName: "chevron.right")
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
struct CompactStreakView: View {
    let accent: Color
    let action: () -> Void
    @ObservedObject private var tracker = PlaytimeTracker.shared
    @AppStorage("ui.goalPeriod") private var goalPeriodRaw = GoalPeriod.weekly.rawValue

    private var goalPeriod: GoalPeriod { GoalPeriod(rawValue: goalPeriodRaw) ?? .weekly }
    private var isPad: Bool { AppLayout.isPad }
    private var scale: CGFloat { isPad ? 1.3 : 1 }
    private var railWidth: CGFloat { isPad ? 104 : 72 }

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
            VStack(spacing: 0) {
                Group {
                    if tracker.streakDays == 0 {
                        Label("streak.dayOne", systemImage: "sparkles")
                            .font(.system(size: 13 * scale, weight: .heavy, design: .rounded))
                    } else {
                        HStack(spacing: 5) {
                            Text(verbatim: "\(tracker.streakDays)")
                                .font(.system(size: 27 * scale, weight: .heavy, design: .rounded))
                            Image(systemName: "flame.fill")
                                .font(.system(size: 16 * scale, weight: .bold))
                        }
                    }
                }
                .foregroundStyle(accent)
                .frame(maxWidth: .infinity, alignment: .center)

                Spacer(minLength: isPad ? 6 : 4)
                progressLine
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer(minLength: isPad ? 6 : 4)

                Text("common.minutesShort \(progressMinutes) \(goalMinutes)")
                    .font(.system(size: 10 * scale, weight: .semibold))
                    .foregroundStyle(accent.opacity(0.6))
                    // The information and its progress rail share one centred
                    // column, so the streak reads as a single compact module.
                    .frame(width: railWidth)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .offset(y: -1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("streak.accessibility.compact \(goalPeriod.title) \(progressMinutes) \(goalMinutes) \(tracker.streakDays)")
        .accessibilityHint("streak.accessibility.choosePeriod")
    }

    private var progressLine: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(accent.opacity(0.15))
                Capsule()
                    .fill(LinearGradient(colors: [accent.opacity(0.6), accent],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, proxy.size.width * dailyProgress))
                    .animation(.snappy(duration: 0.4), value: dailyProgress)
            }
        }
        .frame(width: railWidth, height: 6 * scale)
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
    let celebrationID: UUID?
    var suffix = ""
    // The score waits until the trophy's landing pulse has fully settled.
    var delay = 1.16
    var duration = 0.78
    @State private var startedAt = Date.distantPast
    @State private var startedCelebrationID: UUID?

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(startedAt)
            let progress = celebrationID == nil ? 1 : min(1, max(0, (elapsed - delay) / duration))
            let eased = 1 - pow(1 - progress, 3)
            let value = Int((Double(from) + Double(to - from) * eased).rounded())
            Text(verbatim: "\(value)\(suffix)")
                .contentTransition(.numericText())
                .scaleEffect(1 + sin(progress * .pi) * 0.13)
        }
        .onAppear { beginAnimationIfNeeded() }
        .onChange(of: celebrationID) { _ in beginAnimationIfNeeded() }
        .accessibilityLabel("\(to)\(suffix)")
    }

    private func beginAnimationIfNeeded() {
        guard let celebrationID else {
            startedCelebrationID = nil
            return
        }
        guard startedCelebrationID != celebrationID else { return }
        startedCelebrationID = celebrationID
        startedAt = Date()
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
    var maximumCount = 0
    var maximumCountCelebrationStart: Int?
    var isCelebratingMaximumCount = false
    var celebrationID: UUID?
    /// iPad cards preserve the iPhone design, scaled as one component.
    var cardHeight: CGFloat = 96
    let theme: AnimalCharacter
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

    private var tier: Tier {
        if visibleBest >= ProgressStore.maximumTrophies(for: level) { return .maxed }
        switch visibleBest {
        case ..<1:    return .empty
        case 1...9:   return .one
        case 10...19: return .two
        default:      return .three
        }
    }

    private var isLocked: Bool {
        if case .locked = status { return true }
        return false
    }

    private var isCompleted: Bool { tier == .maxed }

    /// The very first time a level is completed the card gains its gold
    /// border and crown — that milestone gets its own reveal animation and
    /// deliberately skips the theme-color highlight.
    private var isCelebratingFirstMax: Bool {
        isCelebratingMaximumCount && (maximumCountCelebrationStart ?? 0) == 0
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
    /// dots, ribbon) and a `metal` (crown, laurels, border, glow). Whichever
    /// festive color would clash with the active theme is swapped for a violet
    /// accent, guaranteeing strong contrast in every theme.
    private var completedPalette: (hero: Color, metal: Color) {
        let green = Color(red: 0.24, green: 0.60, blue: 0.28)
        let gold = Color(red: 0.87, green: 0.66, blue: 0.12)
        let violet = Color(red: 0.42, green: 0.35, blue: 0.78)
        let h = themeHue
        if (80...175).contains(h) { return (hero: violet, metal: gold) }   // green theme
        if (38...65).contains(h)  { return (hero: green, metal: violet) }   // gold/yellow theme
        return (hero: green, metal: gold)
    }

    /// Trophy counts shown in the menu, always clamped to the maximum — even
    /// when in-game round-off is off and a run pushed the raw score past 30.
    private var displayBest: Int { min(visibleBest, ProgressStore.maximumTrophies(for: level)) }
    private var displayPaused: Int { min(pausedBest, ProgressStore.maximumTrophies(for: level)) }
    private var celebrationDisplayStart: Int {
        min(scoreCelebrationStart ?? displayBest, ProgressStore.maximumTrophies(for: level))
    }
    private var helperMarker: String {
        showsHelperMarker && helperBest > best ? " *" : ""
    }

    /// A lone "1" reads right-of-centre because of its top flag, so its stem
    /// misses the middle dot; nudge just that glyph left to line them up.
    private var numberNudge: CGFloat { level.cardNumber == "1" ? -1 : 0 }

    // MARK: Body

    var body: some View {
        Button(action: action) {
            Group {
                if isCompleted {
                    completedCard
                } else {
                    standardCard
                }
            }
            .frame(height: cardHeight)
            .opacity(isLocked ? 0.55 : 1)
            .scaleEffect((status == .recommended ? 1.02 : 1) * (trophyPulse ? 1.04 : 1))
            .overlay {
                // The completed card draws its own theme highlight *behind*
                // the gold border (see completedCard); only standard cards
                // paint it on top here.
                if (isCelebratingNewScore || isCelebratingMaximumCount) && !isCompleted {
                    RoundedRectangle(cornerRadius: 18 * cardScale)
                        .stroke(theme.deepColor, lineWidth: 4 * cardScale)
                        .shadow(color: theme.color.opacity(0.85), radius: 9 * cardScale)
                        .opacity(highlightOpacity)
                        .allowsHitTesting(false)
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
        } else {
            HStack(spacing: 4 * cardScale) {
                trophyChip
                if isPaused {
                    Rectangle()
                        .fill(theme.deepColor.opacity(0.25))
                        .frame(width: 1, height: 11 * cardScale)
                    HStack(spacing: 2 * cardScale) {
                        Image(systemName: "pause.fill").font(.system(size: 8 * cardScale))
                        Text(verbatim: "\(displayPaused)")
                            .font(.system(size: 11 * cardScale, weight: .bold))
                    }
                    .foregroundStyle(theme.deepColor.opacity(0.7))
                }
            }
        }
    }

    private var trophyChip: some View {
        return HStack(spacing: 3 * cardScale) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 9 * cardScale))
                .scaleEffect(trophyPulse ? 1.48 : 1)
                .rotationEffect(.degrees(trophyPulse ? -12 : 0))
            TrophyCountText(from: celebrationDisplayStart,
                             to: displayBest,
                             celebrationID: isCelebratingNewScore ? celebrationID : nil,
                             suffix: helperMarker)
                .font(.system(size: 12 * cardScale, weight: .bold))
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
        withAnimation(.easeOut(duration: 0.38)) { highlightOpacity = 1 }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.54)) { trophyPulse = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.02) {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.7)) { trophyPulse = false }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.62) {
            withAnimation(.easeOut(duration: 0.42)) { highlightOpacity = 0.32 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.98) {
            withAnimation(.easeOut(duration: 0.2)) { highlightOpacity = 0 }
        }
    }

    private func animateMaximumCountIfNeeded() {
        guard isCelebratingMaximumCount else {
            maximumCountPulse = false
            maximumCountRingOpacity = 0
            firstMaxBorderTrace = 1
            firstMaxCrownScale = 1
            firstMaxCrownOffset = 0
            firstMaxCrownTilt = 0
            firstMaxGlowScale = 1
            firstMaxGlowOpacity = 0
            animatedMaxCelebrationID = nil
            return
        }
        // Run the reveal or pulse exactly once per celebration, even if the
        // grid re-renders and re-appears mid-animation.
        guard let celebrationID, animatedMaxCelebrationID != celebrationID else { return }
        animatedMaxCelebrationID = celebrationID
        if isCelebratingFirstMax {
            animateFirstMaxReveal()
        } else {
            animateRepeatMaxPulse()
        }
    }

    /// First completion: the gold border draws itself around the card, a soft
    /// metal flash blooms outward, and the crown drops in with a small settle.
    /// Timed to finish well inside the celebration's own lifetime so it never
    /// lingers or blocks the eye.
    private func animateFirstMaxReveal() {
        maximumCountPulse = false
        maximumCountRingOpacity = 0
        firstMaxBorderTrace = 0
        firstMaxCrownScale = 0
        firstMaxCrownOffset = -12
        firstMaxCrownTilt = 0
        firstMaxGlowScale = 0.9
        firstMaxGlowOpacity = 0.7

        withAnimation(.easeInOut(duration: 0.55)) { firstMaxBorderTrace = 1 }
        withAnimation(.easeOut(duration: 0.7)) {
            firstMaxGlowScale = 1.3
            firstMaxGlowOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.52)) {
                firstMaxCrownScale = 1
                firstMaxCrownOffset = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.52) {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.42)) { firstMaxCrownTilt = -6 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.74) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { firstMaxCrownTilt = 0 }
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
                        Text(verbatim: "\(displayBest)\(helperMarker)")
                            .font(.system(size: 12 * cardScale, weight: .bold))
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
        // The gold border. On a first completion it traces itself in
        // (firstMaxBorderTrace 0→1); otherwise it rests fully drawn.
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .trim(from: 0, to: firstMaxBorderTrace)
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
                .scaleEffect(firstMaxCrownScale, anchor: .bottom)
                .rotationEffect(.degrees(firstMaxCrownTilt))
                .offset(y: -9 + firstMaxCrownOffset)
        }
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
        }
#else
        fullScreenCover(item: item, onDismiss: onDismiss) { selection in
            GameView(level: selection.level)
        }
#endif
    }
}

#Preview {
    ContentView()
}
