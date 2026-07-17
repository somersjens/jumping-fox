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

/// The six topic filters. Each has a regular menu and an immediate-mix form.
enum MenuFilter: Int, CaseIterable, Identifiable {
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

    func category(for mode: MenuMode) -> ChallengeCategory { standard }
}

enum MenuMode: String, CaseIterable, Identifiable {
    case standard, mix

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "Standard"
        case .mix: return "Mix"
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
    @AppStorage(GameSettings.showStreakKey) private var showsStreak = true
    @AppStorage(GameSettings.showTrophiesKey) private var showsTrophies = true
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
        .alert("Hoe heet je?", isPresented: $showNameEditor) {
            TextField("Naam", text: $nameDraft)
            Button("Bewaar") {
                let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { playerName = trimmed }
            }
            Button("Annuleer", role: .cancel) { }
        }
        .gameCover(item: $selection, onDismiss: { refreshID = UUID() })
    }

    // MARK: Combined top menu

    private var menuCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Button {
                    showPremium = true
                } label: {
                    Group {
                        if character.id == CharacterCatalog.freeCharacterID {
                            Image("no_background")
                                .resizable()
                                .scaledToFill()
                        } else {
                            Text(character.emoji)
                                .font(.system(size: 48))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(.white.opacity(0.75))
                        }
                    }
                    .frame(width: 74, height: 74)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(.white.opacity(0.9), lineWidth: 2)
                    }
                    .shadow(color: character.deepColor.opacity(0.18), radius: 7, y: 3)
                }
                .buttonStyle(.plain)
                .onLongPressGesture(minimumDuration: 2) {
                    onboardingComplete = false
                }
                .accessibilityHint("Houd twee seconden ingedrukt om de onboarding opnieuw te starten")

                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        nameDraft = playerName
                        showNameEditor = true
                    } label: {
                        Text(playerName.isEmpty ? "Jumping Fox" : playerName)
                        .font(.title3.weight(.heavy))
                    }
                    .buttonStyle(.plain)

                    if showsTrophies {
                        Label("\(totalTrophies) trofeeën\(answerHelper ? " *" : "")", systemImage: "trophy.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(character.deepColor.opacity(0.78))
                    }
                }
                .foregroundStyle(character.deepColor)

                Spacer(minLength: 0)

                lifeModeButton
            }

            if showsStreak {
                PlaytimeBar(accent: character.deepColor, isEmbedded: true) {
                    showGoalPicker = true
                }
            }

            Divider().overlay(character.color.opacity(0.22))

            VStack(spacing: 11) {
                HStack(alignment: .center) {
                    Text(selectedFilter.title)
                        .font(.title3.weight(.heavy))
                    if showsTrophies {
                        Label("\(categoryTrophies)\(answerHelper ? " *" : "")", systemImage: "trophy.fill")
                            .font(.subheadline.weight(.bold))
                    }
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

    private var totalTrophies: Int {
        LevelCatalog.byCategory.values.flatMap { $0 }
            .filter { !$0.requiresPremium }
            .reduce(0) { $0 + ProgressStore.bestScore(levelID: $1.id, helperEnabled: answerHelper) }
    }

    private var categoryTrophies: Int {
        LevelCatalog.levels(for: category)
            .filter { !$0.requiresPremium }
            .reduce(0) { $0 + ProgressStore.bestScore(levelID: $1.id, helperEnabled: answerHelper) }
    }

    private var lifeModeButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                lifeModeRaw = lifeMode == .three ? LifeMode.unlimited.rawValue : LifeMode.three.rawValue
            }
        } label: {
            HStack(spacing: 3) {
                if lifeMode == .unlimited {
                    Image(systemName: "infinity")
                } else {
                    Text("3×")
                    Image(systemName: "heart.fill")
                }
            }
            .foregroundStyle(character.deepColor)
            .font(.system(size: 16, weight: .bold))
            .frame(minWidth: 62, minHeight: 49)
            .background(character.color.opacity(0.15), in: Capsule())
            .overlay(Capsule().stroke(character.color.opacity(0.32), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lifeMode == .three ? "Drie levens; tik voor oneindig spelen" : "Oneindig spelen; tik voor drie levens")
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
                .accessibilityLabel("Kies \(modeLabel(mode))")
            }
        }
    }

    private var helperModeRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                showsOptions.toggle()
            } label: {
                HStack {
                    Label("Weergave & spelopties", systemImage: "slider.horizontal.3")
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

                VStack(alignment: .leading, spacing: 10) {
                    optionToggle("Stoppen na 3 levens", isOn: lifeModeBinding)
                    optionToggle("Streak laten zien", isOn: $showsStreak)
                    optionToggle("Trofeeën laten zien", isOn: $showsTrophies)
                    optionToggle("Afronden bij 30 punten", isOn: $capsTrophiesAtThirty)

                    if capsTrophiesAtThirty {
                        Text("Je kunt wel doorspelen, maar je kunt op elk level maximaal 30 punten halen.")
                            .font(.caption)
                            .foregroundStyle(character.deepColor.opacity(0.68))

                        Divider().overlay(character.color.opacity(0.2))
                    }

                    optionToggle("Helpermodus", isOn: $answerHelper)

                    if answerHelper {
                        Text("Het goede antwoord is groen gemarkeerd. Trofeeën worden in deze modus apart geteld.")
                            .font(.caption)
                            .foregroundStyle(character.deepColor.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 10)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(character.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(character.color.opacity(0.18), lineWidth: 1))
    }

    private func optionToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.medium))
            Spacer(minLength: 16)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .tint(character.color)
                .frame(width: 54, height: 32)
                .accessibilityLabel(title)
        }
        .frame(minHeight: 38)
        .foregroundStyle(character.deepColor)
    }

    private var lifeModeBinding: Binding<Bool> {
        Binding(
            get: { lifeMode == .three },
            set: { lifeModeRaw = $0 ? LifeMode.three.rawValue : LifeMode.unlimited.rawValue }
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
                                  showsTrophies: showsTrophies,
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
                                Text("🏆 \(ProgressStore.bestScore(levelID: level.id))\(answerHelper && ProgressStore.helperOnlyBestScore(levelID: level.id) > ProgressStore.bestScore(levelID: level.id) ? " *" : "")")
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
                        Text("Dagelijkse streak")
                            .font(.caption.weight(.heavy))
                        Spacer()
                        Text("\(tracker.todayMinutes)/\(tracker.dailyGoalMinutes) min")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(accent)

                    streakProgressBar

                    Text("\(tracker.streakDays) dagen op rij")
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
        .accessibilityLabel("Daily streak, \(tracker.todayMinutes) of \(tracker.dailyGoalMinutes) minutes")
        .accessibilityHint("Choose a daily goal")
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

struct DailyGoalPicker: View {
    let theme: AnimalCharacter
    @ObservedObject private var tracker = PlaytimeTracker.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dagelijks doel")
                .font(.headline)
            Text("Hoeveel minuten wil je per dag spelen?")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach([5, 10, 15, 20], id: \.self) { minutes in
                    Button("\(minutes)") { tracker.setDailyGoal(minutes) }
                        .font(.subheadline.weight(.bold))
                        .frame(width: 42, height: 36)
                        .background(tracker.dailyGoalMinutes == minutes ? theme.color : .white,
                                    in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(tracker.dailyGoalMinutes == minutes ? .white : theme.deepColor)
                }
            }
        }
        .frame(width: 260)
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
            Label("Premium", systemImage: "lock.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(titleColor.opacity(0.7))
        case .recommended:
            Text("Start here")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(theme.deepColor)
        default:
            scoreLabel(icon: "trophy.fill")
            }
        }
    }

    private func scoreLabel(icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9))
            Text("\(GameSettings.capsTrophiesAtThirty && best >= ProgressStore.maximumTrophiesPerLevel ? "30 MAX" : "\(best)")\(showsHelperMarker && helperBest > best ? " *" : "")")
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
