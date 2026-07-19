//
//  SettingsView.swift
//  Jumping Fox
//
//  Settings sheet: life mode, character selector,
//  and Premium status.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(GameSettings.lifeModeKey) private var lifeModeRaw = LifeMode.three.rawValue
    @AppStorage(GameSettings.answerHintKey) private var answerHintEnabled = true
    @AppStorage(GameSettings.characterKey) private var characterID = "fox"
    @ObservedObject private var premium = PremiumStore.shared
    @ObservedObject private var tracker = PlaytimeTracker.shared
    @ObservedObject private var language = LanguageManager.shared
    @State private var showPremium = false

    private var character: AnimalCharacter { CharacterCatalog.current(isPremium: premium.isPremium) }
    private var lifeMode: LifeMode { LifeMode(rawValue: lifeModeRaw) ?? .three }

    private let characterColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    livesCard
                    hintCard
                    goalsCard
                    characterCard
                    premiumCard
                }
                .padding()
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(character.skyColor.ignoresSafeArea())
            .navigationTitle("settings.title")
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showPremium) {
            PremiumView()
        }
    }

    // MARK: Lives

    private var livesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("settings.lives")
                .font(.headline)

            HStack(spacing: 10) {
                ForEach(LifeMode.allCases) { mode in
                    livesButton(for: mode)
                }
            }

            Text("settings.livesInfo")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
    }

    private func livesButton(for mode: LifeMode) -> some View {
        let isSelected = mode == lifeMode
        let isLocked = mode.requiresPremium && !premium.isPremium
        return Button {
            if isLocked {
                showPremium = true
            } else {
                lifeModeRaw = mode.rawValue
            }
        } label: {
            VStack(spacing: 4) {
                if mode == .unlimited {
                    Image(systemName: "infinity")
                        .font(.title3.weight(.bold))
                } else {
                    Text(verbatim: "\(mode.startingLives ?? 0)")
                        .font(.title3.weight(.heavy))
                }
                Text(mode.label)
                    .font(.caption2.weight(.semibold))
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                isSelected ? AnyShapeStyle(character.color) : AnyShapeStyle(.white),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .foregroundStyle(isSelected ? .white : character.deepColor)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(character.color.opacity(isSelected ? 0 : 0.4), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Hint

    private var hintCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $answerHintEnabled) {
                Text("settings.answerHint")
                    .font(.headline)
            }
            .tint(character.color)

            Text("settings.answerHintInfo")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Play goals

    private var dailyGoal: Binding<Int> {
        Binding(get: { tracker.dailyGoalMinutes }, set: { tracker.setDailyGoal($0) })
    }

    private var goalsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("settings.playGoals")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("settings.dailyGoal")
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 8) {
                    ForEach([5, 10, 15, 20], id: \.self) { minutes in
                        Button {
                            tracker.setDailyGoal(minutes)
                        } label: {
                            Text(verbatim: "\(minutes)")
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    tracker.dailyGoalMinutes == minutes
                                        ? AnyShapeStyle(character.color)
                                        : AnyShapeStyle(.white),
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                                .foregroundStyle(tracker.dailyGoalMinutes == minutes ? .white : character.deepColor)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(character.color.opacity(0.4), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                Stepper("settings.customMinutes \(tracker.dailyGoalMinutes)", value: dailyGoal, in: 1...120)
                    .font(.subheadline)
            }

            Text("settings.goalInfo")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Character selector

    private var characterCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("settings.character")
                    .font(.headline)
                if !premium.isPremium {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LazyVGrid(columns: characterColumns, spacing: 12) {
                ForEach(CharacterCatalog.all) { animal in
                    characterButton(for: animal)
                }
            }

            Text("settings.characterInfo")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
    }

    private func characterButton(for animal: AnimalCharacter) -> some View {
        let isSelected = characterID == animal.id
        let isLocked = animal.id != CharacterCatalog.freeCharacterID && !premium.isPremium
        return Button {
            if isLocked {
                showPremium = true
            } else {
                characterID = animal.id
            }
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(animal.color.opacity(0.22))
                        .frame(width: 52, height: 52)
                    animal.artwork
                        .resizable()
                        .scaledToFit()
                        .frame(width: 46, height: 46)
                        .opacity(isLocked ? 0.5 : 1)
                    if isLocked {
                        Image(systemName: "lock.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .background(.white, in: Circle())
                    }
                }
                .overlay(
                    Circle().stroke(isSelected ? animal.color : .clear, lineWidth: 3)
                )
                Text(animal.localizedName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Premium

    @ViewBuilder
    private var premiumCard: some View {
        if premium.isPremium {
            HStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .foregroundStyle(.yellow)
                Text("settings.premiumUnlocked")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
        } else {
            VStack(spacing: 10) {
                Button {
                    showPremium = true
                } label: {
                    Label("premium.unlock", systemImage: "crown.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(colors: [character.color, character.deepColor],
                                           startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button("premium.restore") {
                    Task { await premium.restorePurchases() }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding()
            .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

#Preview {
    SettingsView()
}
