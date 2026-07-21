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
    @ObservedObject private var language = LanguageManager.shared
    @AppStorage(GameSettings.characterKey) private var characterID = "fox"
    @State private var previewCharacterID = "fox"

    private var character: AnimalCharacter { CharacterCatalog.character(id: previewCharacterID) }
    private var isPad: Bool { AppLayout.isPad }
    private var scale: CGFloat { isPad ? 1.4 : 1 }

    private let characterColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [character.skyColor, character.tintColor],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: isPad ? 28 : 22) {
                    hero
                    if !premium.isPremium {
                        featureCard
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    }
                    characterCard
                    purchaseSection
                }
                .padding(.horizontal, isPad ? 32 : 22)
                .padding(.bottom, isPad ? 38 : 28)
                .frame(maxWidth: isPad ? 760 : 620)
                .frame(maxWidth: .infinity)
            }
            // A form sheet on iPad can be shorter than this purchase flow.
            // Keep the action area reachable even in a short window or with
            // larger accessibility text.
            .scrollBounceBehavior(.always)
            .scrollIndicators(.visible)
        }
        .overlay(alignment: .topLeading) { closeButton }
        .overlay(alignment: .topTrailing) {
            LanguagePicker(tint: character.deepColor.opacity(0.7), scale: isPad ? 1.25 : 1)
                .padding(.top, isPad ? 28 : 24)
                .padding(.trailing, isPad ? 28 : 18)
        }
        .animation(.easeInOut(duration: 0.25), value: previewCharacterID)
        .animation(.spring(response: 0.42, dampingFraction: 0.7), value: premium.isPremium)
        .onAppear { previewCharacterID = characterID }
        .task { await premium.refresh() }
    }

    // MARK: Close

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 17 * scale, weight: .bold))
                .foregroundStyle(character.deepColor)
                .frame(width: 38 * scale, height: 38 * scale)
                .background(.white.opacity(0.7), in: Circle())
                .shadow(color: character.deepColor.opacity(0.15), radius: 6, y: 3)
        }
        .padding(.top, isPad ? 28 : 24)
        .padding(.leading, isPad ? 28 : 18)
    }

    // MARK: Hero — big preview of the selected character

    private var hero: some View {
        VStack(spacing: 12) {
            GeometryReader { proxy in
                let heroSize = min(isPad ? 300 : 240, max(150, proxy.size.width * 0.52))
                ZStack {
                Circle()
                    .fill(
                        RadialGradient(colors: [character.color.opacity(0.35), character.color.opacity(0.05)],
                                       center: .center, startRadius: 6, endRadius: 150)
                    )
                    .frame(width: heroSize, height: heroSize)
                Circle()
                    .stroke(character.color.opacity(0.30), lineWidth: 2)
                    .frame(width: heroSize * 0.92, height: heroSize * 0.92)
                character.artwork
                    .resizable()
                    .scaledToFit()
                    .frame(width: heroSize * 0.88, height: heroSize * 0.88)
                    .shadow(color: character.deepColor.opacity(0.25), radius: 14, y: 8)
                    .id(previewCharacterID)
                    .transition(.scale.combined(with: .opacity))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: isPad ? 300 : 240)

            HStack(spacing: 8) {
                Text(character.localizedName)
                    .font(.system(size: 30 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(character.deepColor)
                if premium.isPremium || previewCharacterID != CharacterCatalog.freeCharacterID {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 22 * scale, weight: .heavy))
                        .foregroundStyle(character.deepColor)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .padding(.top, 44)
    }

    // MARK: Feature card

    private var featureCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            featureRow(icon: "square.grid.3x3.fill",
                       title: L("premium.feature.levels.title"),
                       subtitle: L("premium.feature.levels.subtitle"))
            featureRow(icon: "pawprint.fill",
                       title: L("premium.feature.animals.title"),
                       subtitle: L("premium.feature.animals.subtitle"))
            featureRow(icon: "nosign",
                       title: L("premium.feature.noAds.title"),
                       subtitle: L("premium.feature.noAds.subtitle"))
        }
        .padding(18 * scale)
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
        .padding(18 * scale)
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
                .frame(width: 42 * scale, height: 42 * scale)
                .frame(maxWidth: .infinity)
            .padding(.vertical, 8 * scale)
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
            Button {
                dismiss()
            } label: {
                Text("common.done")
                    .font(isPad ? .system(size: 24, weight: .bold) : .headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14 * scale)
                    .background(character.color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
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
                            Text(purchaseButtonTitle).font(isPad ? .system(size: 24, weight: .bold) : .headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16 * scale)
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

                Text("premium.oneTime")
                    .font(isPad ? .system(size: 20, weight: .regular) : .subheadline)
                    .foregroundStyle(character.deepColor.opacity(0.7))

                Button("premium.restore") {
                    Task { await premium.restorePurchases() }
                }
                .font(isPad ? .system(size: 18, weight: .regular) : .footnote)
                .foregroundStyle(character.deepColor.opacity(0.7))

                if let error = premium.lastError {
                    Text(error)
                        .font(isPad ? .system(size: 18, weight: .regular) : .footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var purchaseButtonTitle: String {
        if let price = premium.product?.displayPrice {
            return L("premium.unlockWithPrice \(price)")
        }
        return L("premium.unlock")
    }

    private func featureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12 * scale) {
            Image(systemName: icon)
                .font(isPad ? .system(size: 28, weight: .regular) : .title3)
                .foregroundStyle(character.color)
                .frame(width: 28 * scale)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(isPad ? .system(size: 24, weight: .bold) : .subheadline.weight(.bold))
                    .foregroundStyle(character.deepColor)
                Text(subtitle)
                    .font(isPad ? .system(size: 20, weight: .regular) : .footnote)
                    .foregroundStyle(character.deepColor.opacity(0.7))
            }
        }
    }

}

/// A purchase flow benefits from the larger page-style iPad presentation:
/// its price and restore controls are visible without an initial scroll.
/// Older supported iOS versions retain the largest available detent.
extension View {
    @ViewBuilder
    func premiumSheetPresentation() -> some View {
        if #available(iOS 18.0, *) {
            self
                .presentationSizing(.page)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        } else {
            self
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

#Preview {
    PremiumView()
}
