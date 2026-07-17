//
//  SettingsView.swift
//  Jumping Fox
//
//  Settings sheet: life mode, answer helper, character selector,
//  and Premium status.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(GameSettings.lifeModeKey) private var lifeModeRaw = LifeMode.one.rawValue
    @AppStorage(GameSettings.answerHelperKey) private var answerHelper = false
    @AppStorage(GameSettings.characterKey) private var characterID = "fox"
    @ObservedObject private var premium = PremiumStore.shared
    @ObservedObject private var tracker = PlaytimeTracker.shared
    @State private var showPremium = false

    private var character: AnimalCharacter { CharacterCatalog.current(isPremium: premium.isPremium) }
    private var lifeMode: LifeMode { LifeMode(rawValue: lifeModeRaw) ?? .one }

    private let characterColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    livesCard
                    goalsCard
                    helperCard
                    characterCard
                    premiumCard
                }
                .padding()
            }
            .background(character.skyColor.ignoresSafeArea())
            .navigationTitle("Settings")
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
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
            Text("Lives")
                .font(.headline)

            HStack(spacing: 10) {
                ForEach(LifeMode.allCases) { mode in
                    livesButton(for: mode)
                }
            }

            Text("The game ends when you run out of lives — or when you fall off the screen! High scores are tracked separately for each mode.")
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
                    Text("\(mode.startingLives ?? 0)")
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

    // MARK: Play goals

    private var dailyGoal: Binding<Int> {
        Binding(get: { tracker.dailyGoalMinutes }, set: { tracker.setDailyGoal($0) })
    }

    private var weeklyGoal: Binding<Int> {
        Binding(get: { tracker.weeklyGoalMinutes }, set: { tracker.setWeeklyGoal($0) })
    }

    private var goalsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Play goals")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Daily goal")
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 8) {
                    ForEach([5, 10, 15, 20], id: \.self) { minutes in
                        Button {
                            tracker.setDailyGoal(minutes)
                        } label: {
                            Text("\(minutes)")
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
                Stepper("Custom: \(tracker.dailyGoalMinutes) min", value: dailyGoal, in: 1...120)
                    .font(.subheadline)
            }

            Divider()

            Stepper("Weekly goal: \(tracker.weeklyGoalMinutes) min", value: weeklyGoal, in: 5...840, step: 5)
                .font(.subheadline)

            Text("Changing the daily goal suggests day × 7 for the week — adjust the weekly goal however you like. Only active playtime counts.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Answer helper

    private var helperCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $answerHelper) {
                Text("Answer helper")
                    .font(.headline)
            }
            .tint(character.color)

            Text("Shows the correct platform in green and wrong ones in red. Great while learning a new table!")
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
                Text("Character")
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

            Text("Every animal brings its own color theme to the whole game.")
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
                    Text(animal.emoji)
                        .font(.system(size: 30))
                        .frame(width: 52, height: 52)
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
                Text(animal.name)
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
                Text("Premium unlocked — thank you!")
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
                    Label("Unlock Premium", systemImage: "crown.fill")
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

                Button("Restore purchases") {
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
