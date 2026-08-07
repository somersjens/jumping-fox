import SwiftUI
import UIKit

// Standalone voorbeeld van de Jumping Fox-einde-levelkaart.
// Vervang deze modellen eventueel door de modellen van de ontvangende app.

enum EndLevelCategory: Equatable {
    case addition, additionMix
    case subtraction, subtractionMix
    case tables, tablesMix
    case fractions, fractionsMix
    case percentages, percentagesMix
    case supermix
}

enum EndLevelMode {
    case order, random, mixed
}

struct EndLevel {
    let category: EndLevelCategory
    let cardNumber: String
    let mode: EndLevelMode

    var trophyGoal: Int {
        if category == .supermix { return 50 }
        switch mode {
        case .order: return 20
        case .random: return 30
        case .mixed: return 40
        }
    }
}

struct EndCardPalette {
    let color: Color
    let deepColor: Color
    let tintColor: Color
    let skyColor: Color
}

struct EndLevelCard: View {
    let level: EndLevel
    let score: Int
    let palette: EndCardPalette
    var showsNewHighScore = false
    var completionSuffix = "afgerond!"
    var completionSubtitle = "Je hebt alle punten gehaald."
    var playAgainTitle = "Nog een keer"
    var menuTitle = "Hoofdmenu"
    let onPlayAgain: () -> Void
    let onMenu: () -> Void

    @State private var isVisible = false
    @State private var celebrate = false

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var layoutScale: CGFloat { isPad ? 1.2 : 1 }
    private var textScale: CGFloat { isPad ? 1.296 : 1 }

    var body: some View {
        ZStack {
            Color.black
                .opacity(isVisible ? 0.56 : 0)
                .ignoresSafeArea()
                .animation(.easeOut(duration: 0.24), value: isVisible)

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        trophyIllustration
                            .padding(.bottom, 18 * layoutScale)

                        completionTitle
                            .frame(maxWidth: .infinity)

                        Text(completionSubtitle)
                            .font(.system(size: 17 * textScale, weight: .medium))
                            .foregroundStyle(palette.deepColor.opacity(0.64))
                            .multilineTextAlignment(.center)
                            .padding(.top, 10 * layoutScale)
                            .frame(minHeight: 30 * layoutScale)

                        scoreCapsule
                            .padding(.top, 22 * layoutScale)

                        buttons
                            .padding(.top, 24 * layoutScale)
                    }
                    .padding(26 * layoutScale)
                    .frame(maxWidth: 400 * layoutScale)
                    .background(cardBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(.white.opacity(0.82), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height, alignment: .center)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.93)
            .offset(y: isVisible ? 0 : 18)
            .animation(
                .spring(response: 0.46, dampingFraction: 0.82),
                value: isVisible
            )
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                isVisible = true
                celebrate = true
            }
        }
    }

    private var cardBackground: some View {
        LinearGradient(
            colors: [palette.skyColor, .white, palette.tintColor],
            startPoint: .top,
            endPoint: .bottom
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var trophyIllustration: some View {
        ZStack {
            Text("✦")
                .font(.system(size: 25 * layoutScale, weight: .bold))
                .foregroundStyle(palette.color.opacity(0.68))
                .offset(x: -54, y: -20)
            Text("✦")
                .font(.system(size: 20 * layoutScale, weight: .bold))
                .foregroundStyle(palette.color.opacity(0.68))
                .offset(x: 53, y: -8)
            Text("🏆")
                .font(.system(size: 70 * layoutScale))
                .scaleEffect(celebrate ? 1 : 0.4)
                .rotationEffect(.degrees(celebrate ? 0 : -25))
                .animation(
                    .spring(response: 0.55, dampingFraction: 0.5),
                    value: celebrate
                )
        }
        .frame(height: 92 * layoutScale)
        .accessibilityHidden(true)
    }

    private var completionTitle: some View {
        let size = 29 * textScale
        return HStack(spacing: 7 * layoutScale) {
            operationLabel(fontSize: size)
            Text(completionSuffix)
                .font(.system(size: size, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundStyle(palette.deepColor)
    }

    @ViewBuilder
    private func operationLabel(fontSize: CGFloat) -> some View {
        let font = Font.system(size: fontSize, weight: .heavy, design: .rounded)
        let number = level.cardNumber

        switch level.category {
        case .addition, .additionMix:
            scalableText("+\(number)", font: font)
        case .subtraction, .subtractionMix:
            scalableText("−\(number)", font: font)
        case .tables, .tablesMix:
            scalableText("×\(number)", font: font)
        case .percentages, .percentagesMix:
            scalableText("\(number)%", font: font)
        case .fractions, .fractionsMix:
            stackedFraction(denominator: number, fontSize: fontSize)
        case .supermix:
            HStack(spacing: 5 * layoutScale) {
                scalableText(number, font: font)
                Image(systemName: "star.fill")
                    .font(.system(size: fontSize * 0.7, weight: .heavy))
            }
        }
    }

    private func scalableText(_ value: String, font: Font) -> some View {
        Text(value)
            .font(font)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }

    private func stackedFraction(denominator: String, fontSize: CGFloat) -> some View {
        let fractionFont = Font.system(
            size: fontSize * 0.6,
            weight: .heavy,
            design: .rounded
        )
        let thickness = max(2, fontSize * 0.07)

        return VStack(spacing: thickness + 3 * layoutScale) {
            Text("1").font(fractionFont).lineLimit(1)
            Text(denominator)
                .font(fractionFont)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .overlay {
            Rectangle()
                .fill(palette.deepColor)
                .frame(height: thickness)
        }
        .fixedSize()
        .padding(.horizontal, 2 * layoutScale)
    }

    private var scoreCapsule: some View {
        Text("\(score) / \(level.trophyGoal)")
            .environment(\.layoutDirection, .leftToRight)
            .font(.system(size: 30 * textScale, weight: .heavy, design: .rounded))
            .foregroundStyle(palette.color)
            .padding(.horizontal, 27 * layoutScale)
            .padding(.vertical, 10 * layoutScale)
            .background(palette.tintColor, in: Capsule())
            .overlay { Capsule().stroke(palette.color.opacity(0.12), lineWidth: 1) }
            .overlay(alignment: .topTrailing) {
                if showsNewHighScore {
                    newHighScoreBadge.offset(x: 30, y: -16)
                }
            }
            .accessibilityLabel("\(score) van \(level.trophyGoal) punten")
    }

    private var newHighScoreBadge: some View {
        Label("Nieuw record", systemImage: "trophy.fill")
            .fixedSize()
            .font(.system(size: 13 * textScale, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 10 * textScale)
            .padding(.vertical, 6 * textScale)
            .background(palette.color, in: Capsule())
            .overlay { Capsule().stroke(.white.opacity(0.45), lineWidth: 1) }
            .shadow(color: palette.deepColor.opacity(0.22), radius: 4, y: 2)
            .scaleEffect(0.8, anchor: .topTrailing)
    }

    private var buttons: some View {
        VStack(spacing: 12 * layoutScale) {
            Button(action: onPlayAgain) {
                Label(playAgainTitle, systemImage: "arrow.counterclockwise")
                    .font(isPad ? .title3.weight(.bold) : .headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14 * layoutScale)
                    .foregroundStyle(.white)
                    .background(
                        LinearGradient(
                            colors: [palette.color, palette.deepColor],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                    )
            }

            Button(action: onMenu) {
                Label(menuTitle, systemImage: "house.fill")
                    .font(isPad ? .title3.weight(.semibold) : .headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14 * layoutScale)
                    .foregroundStyle(palette.deepColor)
                    .background(
                        palette.skyColor,
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke(palette.color.opacity(0.24), lineWidth: 1.5)
                    }
            }
        }
    }
}

struct EndLevelCard_Previews: PreviewProvider {
    static var previews: some View {
        EndLevelCard(
            level: EndLevel(category: .tables, cardNumber: "7", mode: .random),
            score: 30,
            palette: EndCardPalette(
                color: .orange,
                deepColor: .brown,
                tintColor: Color.orange.opacity(0.16),
                skyColor: Color.cyan.opacity(0.16)
            ),
            showsNewHighScore: true,
            onPlayAgain: {},
            onMenu: {}
        )
    }
}
