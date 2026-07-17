//
//  PremiumView.swift
//  Jumping Fox
//
//  Premium purchase sheet: one-time in-app purchase.
//

import SwiftUI
import StoreKit

struct PremiumView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var premium = PremiumStore.shared
    @AppStorage(GameSettings.characterKey) private var characterID = "fox"
    @State private var previewCharacterID = "fox"

    private var character: AnimalCharacter { CharacterCatalog.character(id: previewCharacterID) }

    private let characterColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [character.skyColor, character.tintColor],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    hero
                    featureCard
                    characterCard
                    purchaseSection
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 28)
            }
        }
        .overlay(alignment: .topLeading) { closeButton }
        .animation(.easeInOut(duration: 0.25), value: previewCharacterID)
        .onAppear { previewCharacterID = characterID }
        .task { await premium.refresh() }
    }

    // MARK: Close

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(character.deepColor)
                .frame(width: 38, height: 38)
                .background(.white.opacity(0.7), in: Circle())
                .shadow(color: character.deepColor.opacity(0.15), radius: 6, y: 3)
        }
        .padding(.top, 14)
        .padding(.leading, 18)
    }

    // MARK: Hero — big preview of the selected character

    private var hero: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(colors: [character.color.opacity(0.35), character.color.opacity(0.05)],
                                       center: .center, startRadius: 6, endRadius: 150)
                    )
                    .frame(width: 240, height: 240)
                Circle()
                    .stroke(character.color.opacity(0.30), lineWidth: 2)
                    .frame(width: 220, height: 220)
                character.artwork
                    .resizable()
                    .scaledToFit()
                    .frame(width: 210, height: 210)
                    .shadow(color: character.deepColor.opacity(0.25), radius: 14, y: 8)
                    .id(previewCharacterID)
                    .transition(.scale.combined(with: .opacity))
            }

            HStack(spacing: 8) {
                Text(character.name)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(character.deepColor)
                if previewCharacterID != CharacterCatalog.freeCharacterID {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(character.deepColor)
                }
            }
        }
        .padding(.top, 44)
    }

    // MARK: Feature card

    private var featureCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            featureRow(icon: "square.grid.3x3.fill",
                       title: "100 levels per onderwerp",
                       subtitle: "Altijd genoeg nieuwe sommen om te oefenen.")
            featureRow(icon: "pawprint.fill",
                       title: "Toegang tot alle dieren",
                       subtitle: "Met premium speel je vrij met alle 10 de dieren.")
            featureRow(icon: "nosign",
                       title: "Geen advertenties",
                       subtitle: "Volledig zonder onderbrekingen spelen.")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: Character picker

    private var characterCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: characterColumns, spacing: 8) {
                ForEach(CharacterCatalog.all) { animal in
                    characterCell(for: animal)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func characterCell(for animal: AnimalCharacter) -> some View {
        let isSelected = previewCharacterID == animal.id
        return Button {
            previewCharacterID = animal.id
            if premium.isPremium { characterID = animal.id }
        } label: {
            animal.artwork
                .resizable()
                .scaledToFit()
                .frame(width: 42, height: 42)
                .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? animal.color.opacity(0.18) : .white,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(character.deepColor)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? animal.color : animal.color.opacity(0.2),
                            lineWidth: isSelected ? 2.5 : 1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Purchase

    @ViewBuilder
    private var purchaseSection: some View {
        if premium.isPremium {
            VStack(spacing: 12) {
                Label("You have Premium!", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)

                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(character.color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        } else {
            VStack(spacing: 12) {
                Button {
                    Task {
                        await premium.purchase()
                        if premium.isPremium { characterID = previewCharacterID }
                    }
                } label: {
                    HStack {
                        if premium.isPurchasing {
                            ProgressView().tint(.white)
                        } else {
                            Text(purchaseButtonTitle).font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(colors: [character.color, character.deepColor],
                                       startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .foregroundStyle(.white)
                    .shadow(color: character.deepColor.opacity(0.3), radius: 10, y: 5)
                }
                .buttonStyle(.plain)
                .disabled(premium.isPurchasing)

                Text("One-time purchase. Yours forever.")
                    .font(.subheadline)
                    .foregroundStyle(character.deepColor.opacity(0.7))

                Button("Restore purchases") {
                    Task { await premium.restorePurchases() }
                }
                .font(.footnote)
                .foregroundStyle(character.deepColor.opacity(0.7))

                if let error = premium.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var purchaseButtonTitle: String {
        if let price = premium.product?.displayPrice {
            return "Unlock Premium · \(price)"
        }
        return "Unlock Premium"
    }

    private func featureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(character.color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(character.deepColor)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(character.deepColor.opacity(0.7))
            }
        }
    }
}

#Preview {
    PremiumView()
}
