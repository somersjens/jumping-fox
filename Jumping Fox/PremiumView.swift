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

    private var character: AnimalCharacter { CharacterCatalog.current(isPremium: premium.isPremium) }

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
                           title: "Tables up to 100",
                           subtitle: "Every multiplication table from 13 to 100.")
                featureRow(icon: "infinity",
                           title: "Unlimited lives",
                           subtitle: "Practice as long as you like — falling still ends the game!")
                featureRow(icon: "pawprint.fill",
                           title: "10 characters",
                           subtitle: "Fox, frog, penguin, pig, whale, lion, octopus, crab, turtle, and bear.")
                featureRow(icon: "paintpalette.fill",
                           title: "Matching themes",
                           subtitle: "Every animal colors the whole game in its own style.")
            }
            .padding()
            .background(character.skyColor, in: RoundedRectangle(cornerRadius: 16))

            Spacer()

            if premium.isPremium {
                Label("You have Premium!", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)

                Button("Done") { dismiss() }
                    .font(.headline)
            } else {
                Button {
                    Task { await premium.purchase() }
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
