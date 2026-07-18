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

/// The six topic filters. Each has a regular menu and an immediate-mix form.
enum MenuFilter: Int, CaseIterable, Identifiable {
    case addition, subtraction, tables, fractions, percentages, mixed

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .addition: return String(localized: "filter.addition")
        case .subtraction: return String(localized: "filter.subtraction")
        case .tables: return String(localized: "filter.tables")
        case .fractions: return String(localized: "filter.fractions")
        case .percentages: return String(localized: "filter.percentages")
        case .mixed: return String(localized: "filter.mixed")
        }
    }

    var icon: String {
        switch self {
        case .addition: return "plus.circle.fill"
        case .subtraction: return "minus.circle.fill"
        case .tables: return "multiply.circle.fill"
        case .fractions: return "circle.lefthalf.filled"
        // There is no `percent.circle.fill` SF Symbol. The menu already draws
        // every category inside a circular button, so this remains round while
        // using the supported percent glyph.
        case .percentages: return "percent"
        case .mixed: return "star.circle.fill"
        }
    }

    var standard: ChallengeCategory {
        switch self {
        case .addition: return .addition
        case .subtraction: return .subtraction
        case .tables: return .tables
        case .fractions: return .fractions
        case .percentages: return .percentages
        case .mixed: return .mix
        }
    }

    func category(for mode: MenuMode) -> ChallengeCategory { standard }
}

enum MenuMode: String, CaseIterable, Identifiable {
    case standard, mix

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return String(localized: "mode.standard")
        case .mix: return String(localized: "mode.mix")
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
    @AppStorage(GameSettings.answerHintKey) private var answerHint = true
    @AppStorage(GameSettings.capTrophiesKey) private var capsTrophiesAtThirty = true
    @AppStorage("ui.menuFilter") private var menuFilterRaw = MenuFilter.tables.rawValue
    @AppStorage("ui.menuMode") private var menuModeRaw = MenuMode.standard.rawValue
    @ObservedObject private var premium = PremiumStore.shared
    @State private var selection: LevelSelection?
    @State private var showPremium = false
    @State private var showGoalPicker = false
    @State private var showNameEditor = false
    @State private var nameDraft = ""
    @State private var refreshID = UUID()
    @State private var showsOptions = false
    @State private var expandedOptionInfo: String?
    @State private var headerDetailsHeight: CGFloat = 0

    private var lifeMode: LifeMode { LifeMode(rawValue: lifeModeRaw) ?? .three }
    private var character: AnimalCharacter { CharacterCatalog.current(isPremium: premium.isPremium) }
    private var selectedFilter: MenuFilter { MenuFilter(rawValue: menuFilterRaw) ?? .tables }
    private var menuMode: MenuMode { MenuMode(rawValue: menuModeRaw) ?? .standard }
    private var category: ChallengeCategory { selectedFilter.category(for: menuMode) }

    private let cardColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
    private let miniColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [character.skyColor, character.tintColor],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    menuCard
                    levelGrid
                        .id(showsOptions)
                }
                .padding()
                .id(refreshID)
            }
        }
        .sheet(isPresented: $showPremium) {
            PremiumView()
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
        .gameCover(item: $selection, onDismiss: { refreshID = UUID() })
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

    /// Jumps back to the welcome/onboarding screen. Triggered by a 2-second
    /// hold on the character image.
    private func restartOnboarding() {
#if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
#endif
        onboardingComplete = false
    }

    // MARK: Combined top menu

    private var menuCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                character.artwork
                    .resizable()
                    .scaledToFill()
                    .frame(width: 68, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(.white.opacity(0.9), lineWidth: 2)
                    }
                    .shadow(color: character.deepColor.opacity(0.18), radius: 7, y: 3)
                    .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    // A 2-second hold returns to the welcome flow; a normal tap
                    // still opens the character & premium menu.
                    .onLongPressGesture(minimumDuration: 2) {
                        restartOnboarding()
                    }
                    .onTapGesture {
                        showPremium = true
                    }
                    .accessibilityElement()
                    .accessibilityLabel("menu.accessibility.character")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("menu.accessibility.characterHint")

                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        nameDraft = playerName
                        showNameEditor = true
                    } label: {
                        Text(wrappableName)
                            .font(.title3.weight(.heavy))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .minimumScaleFactor(0.6)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(displayName)
                    }
                    .buttonStyle(.plain)

                    Label {
                        Text(verbatim: String(localized: "menu.trophies \(totalTrophies)") + (answerHelper ? " *" : ""))
                    } icon: {
                        Image(systemName: "trophy.fill")
                    }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(character.deepColor.opacity(0.78))
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
                .frame(width: 106, height: headerDetailsHeight > 0 ? headerDetailsHeight : nil)
            }
            .onPreferenceChange(HeaderDetailsHeightKey.self) { headerDetailsHeight = $0 }

            Divider().overlay(character.color.opacity(0.22))

            VStack(spacing: 11) {
                HStack(alignment: .center) {
                    Text(selectedFilter.title)
                        .font(.title3.weight(.heavy))
                    Label {
                        Text(verbatim: "\(categoryTrophies)\(answerHelper ? " *" : "")")
                    } icon: {
                        Image(systemName: "trophy.fill")
                    }
                        .font(.subheadline.weight(.bold))
                    Spacer()
                }
                .foregroundStyle(character.deepColor)

                HStack(spacing: 6) {
                    ForEach(MenuFilter.allCases) { filter in
                        menuFilterButton(filter)
                    }
                }

                menuModePicker

                helperModeRow
            }
        }
        .padding(14)
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
            withAnimation(.snappy(duration: 0.2)) { menuFilterRaw = filter.rawValue }
        } label: {
            menuFilterIcon(filter, isSelected: isSelected)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(isSelected ? character.color : .white.opacity(0.7), in: Circle())
            .overlay(Circle().stroke(character.color.opacity(isSelected ? 0 : 0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func menuFilterIcon(_ filter: MenuFilter, isSelected: Bool) -> some View {
        if filter == .percentages {
            // SF Symbols has no percent.circle.fill. Draw a matching circular
            // percent badge ourselves, so it aligns with the other topic icons.
            Image(systemName: "percent")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(isSelected ? character.color : .white)
                .frame(width: 20, height: 20)
                // Use the same deep theme colour as the other unselected
                // symbols, rather than a fixed/light orange.
                .background(isSelected ? .white : character.deepColor, in: Circle())
        } else {
            Image(systemName: filter.icon)
                .font(.title3.weight(.bold))
                .foregroundStyle(isSelected ? .white : character.deepColor)
        }
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

    /// Trophies earned for a base level, counting both its standard and Mix-mode
    /// variants and any in-progress paused run — whichever is highest. This is
    /// why a paused (or Mix) level still adds to the category and grand totals.
    private func trophies(for level: LevelConfig) -> Int {
        let ids = Set([level.id, level.immediateMixVersion().id])
        let recorded = ids.map {
            ProgressStore.bestScore(levelID: $0, helperEnabled: answerHelper)
        }.max() ?? 0
        let pausedRaw = ids.map {
            PausedGameStore.shared.pausedScore(forLevelID: $0, includingHelper: answerHelper)
        }.max() ?? 0
        let paused = capsTrophiesAtThirty
            ? min(ProgressStore.maximumTrophiesPerLevel, pausedRaw)
            : pausedRaw
        return max(recorded, paused)
    }

    /// In the Mix menu the mode buttons show exactly which operations they
    /// contain — "Standard"/"Mix" alone doesn't mean anything there.
    private func modeLabel(_ mode: MenuMode) -> String {
        guard selectedFilter == .mixed else { return mode.title }
        return mode == .standard ? "+ − ×" : "+ − × ÷ %"
    }

    private var menuModePicker: some View {
        HStack(spacing: 8) {
            ForEach(MenuMode.allCases) { mode in
                let isSelected = menuMode == mode
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        menuModeRaw = mode.rawValue
                    }
                } label: {
                    Text(modeLabel(mode))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(isSelected ? .white : character.deepColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(isSelected ? character.color : .white.opacity(0.62), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(character.color.opacity(isSelected ? 0 : 0.28), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("menu.accessibility.chooseMode \(modeLabel(mode))")
            }
        }
    }

    private var helperModeRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                showsOptions.toggle()
            } label: {
                HStack {
                    Label("menu.options", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.bold))
                    Spacer()
                    Image(systemName: showsOptions ? "chevron.up" : "chevron.down")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(character.deepColor)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsOptions {
                Divider()
                    .overlay(character.color.opacity(0.2))
                    .padding(.top, 9)

                VStack(alignment: .leading, spacing: 0) {
                    let rows: [(String, Binding<Bool>, String)] = [
                        (String(localized: "options.capAt30.title"), $capsTrophiesAtThirty,
                         String(localized: "options.capAt30.info")),
                        (String(localized: "options.unlimitedLives.title"), unlimitedLivesBinding,
                         String(localized: "options.unlimitedLives.info")),
                        (String(localized: "options.answerHint.title"), $answerHint,
                         String(localized: "options.answerHint.info")),
                        (String(localized: "options.helperMode.title"), $answerHelper,
                         String(localized: "options.helperMode.info")),
                    ]
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 {
                            Divider().overlay(character.color.opacity(0.14))
                        }
                        optionRow(row.0, isOn: row.1, info: row.2)
                    }
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.top, 10)
        // No dead space under the last row when the list is open — keep the
        // header symmetric when it's closed.
        .padding(.bottom, showsOptions ? 2 : 10)
        .background(character.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(character.color.opacity(0.18), lineWidth: 1))
    }

    /// A settings row: tap the title (or the info icon, or anywhere in the
    /// text area) to expand a short explanation; the toggle works on its own.
    private func optionRow(_ title: String, isOn: Binding<Bool>, info: String) -> some View {
        let isExpanded = expandedOptionInfo == title
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.28)) {
                        expandedOptionInfo = isExpanded ? nil : title
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.leading)
                        Image(systemName: isExpanded ? "info.circle.fill" : "info.circle")
                            .font(.footnote)
                            .foregroundStyle(character.color)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Toggle(title, isOn: isOn)
                    .labelsHidden()
                    .tint(character.color)
                    .scaleEffect(0.8, anchor: .trailing)
                    .accessibilityLabel(title)
            }
            .frame(minHeight: 38)

            if isExpanded {
                Text(info)
                    .font(.footnote)
                    .lineSpacing(2)
                    .foregroundStyle(character.deepColor.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 30)
                    .padding(.bottom, 10)
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
            menuMode == .mix ? $0.immediateMixVersion() : $0
        }
        let regular = levels.filter { !$0.requiresPremium }
        let premiumLevels = levels.filter { $0.requiresPremium }
        let hasProgress = levels.contains {
            ProgressStore.bestScore(levelID: $0.id, helperEnabled: true) > 0
        }
        let recommendedID = hasProgress ? nil : regular.first?.id

        return VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: cardColumns, spacing: 12) {
                ForEach(regular) { level in
                    let normalBest = ProgressStore.bestScore(levelID: level.id)
                    LevelCardView(level: level,
                                  status: status(for: level, recommendedID: recommendedID),
                                  best: normalBest,
                                  helperBest: ProgressStore.helperOnlyBestScore(levelID: level.id),
                                  showsHelperMarker: answerHelper,
                                  showsTrophies: true,
                                  isPaused: PausedGameStore.shared.hasPausedSession(for: level, mode: lifeMode),
                                  theme: character) {
                        selection = LevelSelection(level: level)
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
            VStack(alignment: .leading, spacing: 8) {
                Text("menu.premiumTables")
                    .font(.headline)
                    .foregroundStyle(character.deepColor)
                LazyVGrid(columns: miniColumns, spacing: 8) {
                    ForEach(levels) { level in
                        Button {
                            selection = LevelSelection(level: level)
                        } label: {
                            VStack(spacing: 2) {
                                Text(level.cardNumber)
                                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.white)
                                Text(verbatim: "🏆 \(ProgressStore.bestScore(levelID: level.id))\(answerHelper && ProgressStore.helperOnlyBestScore(levelID: level.id) > ProgressStore.bestScore(levelID: level.id) ? " *" : "")")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(character.deepColor, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else {
            Button {
                showPremium = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "crown.fill")
                        .foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("menu.moreLevels")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                        Text("menu.unlockWithPremium")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    Spacer()
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(14)
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
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                    } else {
                        HStack(spacing: 5) {
                            Text(verbatim: "\(tracker.streakDays)")
                                .font(.system(size: 27, weight: .heavy, design: .rounded))
                            Image(systemName: "flame.fill")
                                .font(.system(size: 16, weight: .bold))
                        }
                    }
                }
                .foregroundStyle(accent)
                .frame(maxWidth: .infinity, alignment: .center)
                // `sparkles` has more empty canvas on its leading side; this
                // keeps the visible star + title centred over the bar.
                .offset(x: tracker.streakDays == 0 ? 13 : 17)

                Spacer(minLength: 4)
                progressLine
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Spacer(minLength: 4)

                Text("common.minutesShort \(progressMinutes) \(goalMinutes)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent.opacity(0.6))
                    // Align the text's visual bottom with the trophy line.
                    .offset(x: 17, y: -1)
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
        .frame(width: 72, height: 6)
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
        .onAppear { focused = true }
    }
}

private enum GoalPeriod: String, CaseIterable, Identifiable {
    case daily
    case weekly

    var id: String { rawValue }
    var title: String {
        self == .daily
            ? String(localized: "goalPeriod.daily")
            : String(localized: "goalPeriod.weekly")
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

/// Compact level card. Empty levels are intentionally available in a soft
/// grey; a lock is reserved solely for Premium content.
struct LevelCardView: View {
    let level: LevelConfig
    let status: LevelCardStatus
    let best: Int
    let helperBest: Int
    let showsHelperMarker: Bool
    let showsTrophies: Bool
    let isPaused: Bool
    let theme: AnimalCharacter
    let action: () -> Void

    private var isLocked: Bool {
        if case .locked = status { return true }
        return false
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(level.cardNumber)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(titleColor)
                    .frame(maxWidth: .infinity)

                bottomLine
            }
            .padding(8)
            .frame(height: 82)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(borderColor, lineWidth: status == .recommended ? 3 : 1.5)
            )
            .opacity(isLocked ? 0.55 : 1)
            .scaleEffect(status == .recommended ? 1.03 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
    }

    // MARK: Pieces

    @ViewBuilder
    private var bottomLine: some View {
        if !showsTrophies {
            if isPaused {
                Image(systemName: "pause.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(titleColor.opacity(0.75))
            } else {
                EmptyView()
            }
        } else if isPaused {
            scoreLabel(icon: "pause.fill")
        } else {
            switch status {
        case .locked(let progress) where progress > 0:
            // "Almost unlocked": show how close the previous level is.
            ProgressView(value: progress)
                .tint(theme.color)
                .scaleEffect(y: 0.7)
        case .locked:
            Label("menu.premium", systemImage: "lock.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(titleColor.opacity(0.7))
        case .recommended:
            Text("menu.startHere")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(theme.deepColor)
        default:
            scoreLabel(icon: "trophy.fill")
            }
        }
    }

    private func scoreLabel(icon: String) -> some View {
        let marker = showsHelperMarker && helperBest > best ? " *" : ""
        let isMax = GameSettings.capsTrophiesAtThirty && best >= ProgressStore.maximumTrophiesPerLevel
        return HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9))
            Group {
                if isMax {
                    Text(verbatim: String(localized: "menu.maxScore") + marker)
                } else {
                    Text(verbatim: "\(best)\(marker)")
                }
            }
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(status == .completed ? .white : theme.deepColor.opacity(0.8))
    }

    private var titleColor: Color {
        status == .completed ? .white : theme.deepColor
    }

    private var cardBackground: some ShapeStyle {
        switch status {
        case .completed:
            return AnyShapeStyle(
                LinearGradient(colors: [theme.color, theme.deepColor],
                               startPoint: .top, endPoint: .bottom)
            )
        case .locked:
            return AnyShapeStyle(Color.white.opacity(0.5))
        default:
            return AnyShapeStyle(best == 0 ? Color.white.opacity(0.5) : Color.white.opacity(0.9))
        }
    }

    private var borderColor: Color {
        switch status {
        case .recommended: return theme.color
        case .completed: return theme.deepColor
        case .locked: return theme.deepColor.opacity(0.25)
        case .available: return theme.color.opacity(0.5)
        }
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
