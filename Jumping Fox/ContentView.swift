//
//  ContentView.swift
//  Jumping Fox
//
//  Home screen: playtime progress, cyclic category selector with
//  arrow navigation (plus optional swipe), and redesigned level
//  cards with a big central number.
//

import SwiftUI

struct LevelSelection: Identifiable {
    let level: LevelConfig
    var id: String { level.id }
}

/// The six topic filters. Each has a regular menu, its immediate-mix form,
/// and the more varied challenge menu.
private enum MenuFilter: Int, CaseIterable, Identifiable {
    case addition, subtraction, tables, fractions, percentages, mixed

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .addition: return "Addition"
        case .subtraction: return "Subtraction"
        case .tables: return "Tables"
        case .fractions: return "Fractions"
        case .percentages: return "Percentages"
        case .mixed: return "Mix"
        }
    }

    var icon: String {
        switch self {
        case .addition: return "plus.circle.fill"
        case .subtraction: return "minus.circle.fill"
        case .tables: return "multiply.circle.fill"
        case .fractions: return "circle.lefthalf.filled"
        case .percentages: return "percent"
        case .mixed: return "shuffle.circle.fill"
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

    var challenge: ChallengeCategory {
        switch self {
        case .addition: return .additionMix
        case .subtraction: return .subtractionMix
        case .tables: return .tablesMix
        case .fractions: return .fractionsMix
        case .percentages: return .percentagesMix
        case .mixed: return .supermix
        }
    }

    func category(for mode: MenuMode) -> ChallengeCategory {
        mode == .challenge ? challenge : standard
    }
}

private enum MenuMode: String, CaseIterable, Identifiable {
    case standard, mix, challenge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "Standard"
        case .mix: return "Mix"
        case .challenge: return "Challenge"
        }
    }
}

// MARK: - Home screen

struct ContentView: View {
    @AppStorage(GameSettings.characterKey) private var characterID = "fox"
    @AppStorage(GameSettings.lifeModeKey) private var lifeModeRaw = LifeMode.one.rawValue
    @AppStorage("ui.menuFilter") private var menuFilterRaw = MenuFilter.tables.rawValue
    @AppStorage("ui.menuMode") private var menuModeRaw = MenuMode.standard.rawValue
    @ObservedObject private var premium = PremiumStore.shared
    @State private var selection: LevelSelection?
    @State private var showSettings = false
    @State private var showPremium = false
    @State private var refreshID = UUID()

    private var lifeMode: LifeMode { LifeMode(rawValue: lifeModeRaw) ?? .one }
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
                    header
                    PlaytimeBar(accent: character.deepColor) {
                        showSettings = true
                    }
                    categorySelector
                    levelGrid
                }
                .padding()
                .id(refreshID)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundStyle(character.deepColor)
                    .padding(10)
                    .background(.white.opacity(0.7), in: Circle())
            }
            .padding(.trailing, 16)
            .padding(.top, 4)
        }
        .sheet(isPresented: $showSettings, onDismiss: { refreshID = UUID() }) {
            SettingsView()
        }
        .sheet(isPresented: $showPremium) {
            PremiumView()
        }
        .gameCover(item: $selection, onDismiss: { refreshID = UUID() })
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 4) {
            Text(character.emoji)
                .font(.system(size: 56))
            Button {
                showSettings = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: lifeMode == .unlimited ? "infinity" : "heart.fill")
                        .foregroundStyle(.red)
                    Text(lifeMode.label)
                        .foregroundStyle(character.deepColor)
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.white.opacity(0.7), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    // MARK: Menu filters

    private var categorySelector: some View {
        VStack(spacing: 12) {
            Text(selectedFilter.title)
                .font(.title3.weight(.heavy))
                .foregroundStyle(character.deepColor)

            HStack {
                Text("Total score")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Label("\(groupTotalScore)", systemImage: "trophy.fill")
                    .font(.headline.weight(.heavy))
            }
            .foregroundStyle(character.deepColor)

            HStack(spacing: 6) {
                ForEach(MenuFilter.allCases) { filter in
                    menuFilterButton(filter)
                }
            }

            Picker("Menu type", selection: $menuModeRaw) {
                ForEach(MenuMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .tint(character.color)
            .accessibilityLabel("Choose standard or mix menu")
        }
        .padding(12)
        .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
    }

    private func menuFilterButton(_ filter: MenuFilter) -> some View {
        let isSelected = filter == selectedFilter
        return Button {
            withAnimation(.snappy(duration: 0.2)) { menuFilterRaw = filter.rawValue }
        } label: {
            Image(systemName: filter.icon)
                .font(.title3.weight(.bold))
            .foregroundStyle(isSelected ? .white : character.deepColor)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(isSelected ? character.color : .white.opacity(0.7), in: Circle())
            .overlay(Circle().stroke(character.color.opacity(isSelected ? 0 : 0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var groupTotalScore: Int {
        let standardLevels = LevelCatalog.levels(for: selectedFilter.standard)
        let allModes = standardLevels
            + standardLevels.map { $0.immediateMixVersion() }
            + LevelCatalog.levels(for: selectedFilter.challenge)
        return allModes
            .filter { !$0.requiresPremium }
            .reduce(0) { $0 + ProgressStore.bestScore(levelID: $1.id, mode: lifeMode) }
    }

    // MARK: Level grid

    private var levelGrid: some View {
        let levels = LevelCatalog.levels(for: category).map {
            menuMode == .mix ? $0.immediateMixVersion() : $0
        }
        let regular = levels.filter { !$0.requiresPremium }
        let premiumLevels = levels.filter { $0.requiresPremium }
        let recommendedID = regular.first?.id

        return VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: cardColumns, spacing: 12) {
                ForEach(regular) { level in
                    LevelCardView(level: level,
                                  status: status(for: level, recommendedID: recommendedID),
                                  best: ProgressStore.bestScore(levelID: level.id, mode: lifeMode),
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
                Text("Premium tables")
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
                                Text("🏆 \(ProgressStore.bestScore(levelID: level.id, mode: lifeMode))")
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
                        Text("More levels")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                        Text("Unlock more with Premium")
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

// MARK: - Playtime bar

/// A single daily streak goal. Tapping it opens Settings to adjust the
/// default five-minute goal.
struct PlaytimeBar: View {
    let accent: Color
    let action: () -> Void
    @ObservedObject private var tracker = PlaytimeTracker.shared

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
            HStack {
                    Label("Daily streak", systemImage: "flame.fill")
                Spacer()
                Text("\(tracker.todayMinutes)/\(tracker.dailyGoalMinutes) min")
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .opacity(0.65)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(accent)

            ProgressView(value: dailyProgress)
                .tint(accent)
                .scaleEffect(y: 0.8)

                Text("\(tracker.streakDays) day streak")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accent.opacity(0.8))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Daily streak, \(tracker.todayMinutes) of \(tracker.dailyGoalMinutes) minutes")
        .accessibilityHint("Opens settings to change the daily goal")
    }

    private var dailyProgress: Double {
        min(1, Double(tracker.todayMinutes) / Double(max(1, tracker.dailyGoalMinutes)))
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
        switch status {
        case .locked(let progress) where progress > 0:
            // "Almost unlocked": show how close the previous level is.
            ProgressView(value: progress)
                .tint(theme.color)
                .scaleEffect(y: 0.7)
        case .locked:
            Label("Premium", systemImage: "lock.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(titleColor.opacity(0.7))
        case .recommended:
            Text("Start here")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(theme.deepColor)
        default:
            HStack(spacing: 3) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 9))
                Text("\(best)")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(status == .completed ? .white : theme.deepColor.opacity(0.8))
        }
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
