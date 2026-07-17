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

// MARK: - Home screen

struct ContentView: View {
    @AppStorage(GameSettings.characterKey) private var characterID = "fox"
    @AppStorage(GameSettings.lifeModeKey) private var lifeModeRaw = LifeMode.one.rawValue
    @AppStorage("ui.categoryIndex") private var categoryIndex = 4 // Times Tables by default
    @ObservedObject private var premium = PremiumStore.shared
    @State private var selection: LevelSelection?
    @State private var showSettings = false
    @State private var showPremium = false
    @State private var refreshID = UUID()
    @State private var lastCategorySwitch = Date.distantPast

    private var lifeMode: LifeMode { LifeMode(rawValue: lifeModeRaw) ?? .one }
    private var character: AnimalCharacter { CharacterCatalog.current(isPremium: premium.isPremium) }
    private var category: ChallengeCategory {
        let all = ChallengeCategory.allCases
        return all[((categoryIndex % all.count) + all.count) % all.count]
    }

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
                    PlaytimeBar(accent: character.deepColor)
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
            Text("Jumping Fox")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(character.deepColor)

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

    // MARK: Category selector

    private var categorySelector: some View {
        HStack(spacing: 8) {
            arrowButton(systemName: "chevron.left") { switchCategory(-1) }

            VStack(spacing: 2) {
                Text(category.displayName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(character.deepColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.opacity)
                Text("\(ChallengeCategory.allCases.firstIndex(of: category)! + 1) / \(ChallengeCategory.allCases.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(character.deepColor.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .animation(.snappy(duration: 0.2), value: categoryIndex)

            arrowButton(systemName: "chevron.right") { switchCategory(1) }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
        // Swipe is supported in addition to (never instead of) the arrows.
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.width < -40 { switchCategory(1) }
                    else if value.translation.width > 40 { switchCategory(-1) }
                }
        )
    }

    private func arrowButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44) // always visible, comfortably tappable
                .background(character.color, in: Circle())
        }
        .buttonStyle(.plain)
    }

    /// Cyclic navigation with a short debounce so rapid taps can't
    /// cause double switches or broken state.
    private func switchCategory(_ delta: Int) {
        let now = Date()
        guard now.timeIntervalSince(lastCategorySwitch) > 0.25 else { return }
        lastCategorySwitch = now
        let count = ChallengeCategory.allCases.count
        withAnimation(.snappy(duration: 0.2)) {
            categoryIndex = ((categoryIndex + delta) % count + count) % count
        }
    }

    // MARK: Level grid

    private var levelGrid: some View {
        let levels = LevelCatalog.levels(for: category)
        let regular = levels.filter { !$0.requiresPremium }
        let premiumLevels = levels.filter { $0.requiresPremium }
        let recommendedID = recommendedLevelID(in: regular)

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
        if !ProgressStore.isUnlocked(level) {
            return .locked(progress: ProgressStore.unlockProgress(level))
        }
        if ProgressStore.isCompleted(level) {
            return .completed
        }
        if level.id == recommendedID {
            return .recommended
        }
        return .available
    }

    private func recommendedLevelID(in levels: [LevelConfig]) -> String? {
        levels.first { ProgressStore.isUnlocked($0) && !ProgressStore.isCompleted($0) }?.id
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
                        Text("Tables 13–100")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                        Text("Unlock with Premium")
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

/// Compact progress line: today, week, streak. Only re-renders when a
/// minute value or the streak actually changes.
struct PlaytimeBar: View {
    let accent: Color
    @ObservedObject private var tracker = PlaytimeTracker.shared

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 4) {
                Text("Today \(tracker.todayMinutes)/\(tracker.dailyGoalMinutes) min")
                Text("·")
                Text("Week \(tracker.weekMinutes)/\(tracker.weeklyGoalMinutes) min")
                Text("·")
                Text("🔥 \(tracker.streakDays)")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(accent)
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            ProgressView(value: min(1, Double(tracker.todayMinutes) / Double(max(1, tracker.dailyGoalMinutes))))
                .tint(accent)
                .scaleEffect(y: 0.8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Level cards

enum LevelCardStatus: Equatable {
    case locked(progress: Double)  // progress toward unlocking (0–1)
    case available
    case recommended
    case completed
}

/// Redesigned card: big central number first, small operation symbol
/// second. Status is communicated with border, icon, opacity, label,
/// scale and progress — never with color alone.
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
            VStack(spacing: 2) {
                // Secondary: small operation symbol + short category label.
                HStack {
                    Text(level.category.symbol)
                        .font(.footnote.weight(.heavy))
                        .foregroundStyle(titleColor.opacity(0.8))
                    Spacer()
                    statusIcon
                }

                // Primary: the big, dominant number.
                Text(level.cardNumber)
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(titleColor)
                    .frame(maxWidth: .infinity)

                bottomLine
            }
            .padding(10)
            .frame(height: 104)
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
    private var statusIcon: some View {
        switch status {
        case .locked:
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(titleColor.opacity(0.8))
        case .completed:
            Image(systemName: "checkmark.seal.fill")
                .font(.caption)
                .foregroundStyle(.white)
        case .recommended:
            Image(systemName: "star.fill")
                .font(.caption)
                .foregroundStyle(.yellow)
        case .available:
            if level.isAdvanced {
                Image(systemName: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(theme.deepColor.opacity(0.7))
            }
        }
    }

    @ViewBuilder
    private var bottomLine: some View {
        switch status {
        case .locked(let progress) where progress > 0:
            // "Almost unlocked": show how close the previous level is.
            ProgressView(value: progress)
                .tint(theme.color)
                .scaleEffect(y: 0.7)
        case .locked:
            Text("Locked")
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
            return AnyShapeStyle(Color.white.opacity(0.9))
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
