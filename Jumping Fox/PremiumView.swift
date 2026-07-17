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

    var body: some View {
        VStack(spacing: 22) {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }

            Image(systemName: "crown.fill")
                .font(.system(size: 52))
                .foregroundStyle(.yellow)

            Text("Jumping Fox Premium")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(character.deepColor)

            Text("One-time purchase. Yours forever.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                featureRow(icon: "square.grid.3x3.fill",
                           title: "100 levels per onderwerp",
                           subtitle: "Altijd genoeg nieuwe sommen om te oefenen.")
                featureRow(icon: "pawprint.fill",
                           title: "Kies je eigen poppetje",
                           subtitle: "Kies hieronder jouw favoriete dier.")
                featureRow(icon: "nosign",
                           title: "Geen advertenties",
                           subtitle: "Volledig zonder onderbrekingen spelen.")
            }
            .padding()
            .background(character.skyColor, in: RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 10) {
                Text("Kies je poppetje")
                    .font(.headline)
                    .foregroundStyle(character.deepColor)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                    ForEach(CharacterCatalog.all) { animal in
                        Button {
                            previewCharacterID = animal.id
                            if premium.isPremium { characterID = animal.id }
                        } label: {
                            VStack(spacing: 2) {
                                Text(animal.emoji).font(.system(size: 29))
                                Text(animal.name).font(.system(size: 8, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(previewCharacterID == animal.id ? character.color : .white,
                                        in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(previewCharacterID == animal.id ? .white : character.deepColor)
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(character.color.opacity(0.35), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !premium.isPremium {
                    Text("Tik op een dier om het te bekijken. Na aankoop wordt je keuze meteen toegepast.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if premium.isPremium {
                Label("You have Premium!", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)

                Button("Done") { dismiss() }
                    .font(.headline)
            } else {
                Button {
                    Task {
                        await premium.purchase()
                        if premium.isPremium { characterID = previewCharacterID }
                    }
                } label: {
                    HStack {
                        if premium.isPurchasing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text(purchaseButtonTitle)
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(colors: [character.color, character.deepColor],
                                       startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(premium.isPurchasing)

                Button("Restore purchases") {
                    Task { await premium.restorePurchases() }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                if let error = premium.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(24)
        .onAppear { previewCharacterID = characterID }
        .task { await premium.refresh() }
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
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    PremiumView()
}
