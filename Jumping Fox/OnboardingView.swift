import SwiftUI

struct OnboardingView: View {
    @AppStorage(GameSettings.playerNameKey) private var playerName = ""
    @AppStorage(GameSettings.onboardingCompleteKey) private var isComplete = false
    @AppStorage("ui.menuFilter") private var menuFilterRaw = MenuFilter.tables.rawValue
    @AppStorage("ui.menuMode") private var menuModeRaw = PracticeMode.order.rawValue
    @AppStorage("ui.supermixCategory") private var supermixCategoryRaw = ChallengeCategory.superBasic.rawValue
    @ObservedObject private var language = LanguageManager.shared
    @State private var step = 0
    @FocusState private var isNameFieldFocused: Bool

    private var isPad: Bool { AppLayout.isPad }
    private var contentWidth: CGFloat { isPad ? 640 : 500 }

    var body: some View {
        ZStack {
            onboardingBackground

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Image("no_background")
                            .resizable()
                            .scaledToFit()
                            .frame(width: isPad ? (step == 1 ? 160 : 210) : (step == 1 ? 112 : 150),
                                   height: isPad ? (step == 1 ? 160 : 210) : (step == 1 ? 112 : 150))
                            .padding(.bottom, isPad ? (step == 1 ? 20 : 30) : (step == 1 ? 14 : 22))
                            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: step)

                        Group {
                            switch step {
                            case 0: nameStep
                            case 1: subjectStep
                            default: levelStep
                            }
                        }
                        .id(step)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                    .frame(maxWidth: contentWidth)
                    .padding(.horizontal, isPad ? 36 : 24)
                    .padding(.vertical, isPad ? 40 : 28)
                    // On normal-height screens this fills the viewport and
                    // centres the welcome content. On smaller screens the
                    // content simply grows taller and remains scrollable.
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .foregroundStyle(Color(red: 0.43, green: 0.20, blue: 0.03))
        .overlay(alignment: .topLeading) {
            // Steps 2 and 3 can step back to correct a wrong choice. Mirrors
            // the language flag: same glass style, same top inset, left corner.
            if step > 0 {
                backButton
                    .padding(.top, isPad ? 20 : 8)
                    .padding(.leading, isPad ? 28 : 16)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            LanguagePicker(tint: Color(red: 0.43, green: 0.20, blue: 0.03).opacity(0.6),
                           scale: isPad ? 1.25 : 1)
                .padding(.top, isPad ? 20 : 8)
                .padding(.trailing, isPad ? 28 : 16)
        }
    }

    private var backButton: some View {
        Button {
            advance(to: step - 1)
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: isPad ? 26 : 22, weight: .semibold))
                .foregroundStyle(Color(red: 0.43, green: 0.20, blue: 0.03).opacity(0.6))
                .padding(.horizontal, isPad ? 16 : 13)
                .padding(.vertical, isPad ? 11 : 8)
                .liquidGlassCapsule()
                .contentShape(Capsule())
        }
        .accessibilityLabel(Text("common.back"))
    }

    private var onboardingBackground: some View {
        LinearGradient(
            colors: [Color.orange.opacity(0.24), Color.yellow.opacity(0.13)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var nameStep: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Text("onboarding.name.title")
                    .font(.system(size: isPad ? 50 : 35, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)

                Text("onboarding.name.subtitle")
                    .font(isPad ? .title.weight(.medium) : .title3.weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            TextField(String(), text: $playerName, prompt: Text("name.placeholder"))
                .font(.system(size: isPad ? 38 : 26, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .focused($isNameFieldFocused)
                .textContentType(.name)
                .submitLabel(.next)
                .onSubmit { goToSubjects() }
                .padding(.horizontal, isPad ? 22 : 16)
                .padding(.vertical, isPad ? 18 : 14)
                .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isNameFieldFocused ? Color.orange : .brown.opacity(0.18),
                                lineWidth: isNameFieldFocused ? 2 : 1)
                )
                .frame(maxWidth: isPad ? 400 : 300)
                .animation(.snappy(duration: 0.2), value: isNameFieldFocused)

            Button("common.continue") { goToSubjects() }
                .buttonStyle(OnboardingButtonStyle(isPad: isPad))
                .frame(maxWidth: isPad ? 360 : .infinity)
        }
    }

    private var subjectStep: some View {
        VStack(spacing: 14) {
            Text("onboarding.subject.title")
                .font(.system(size: isPad ? 46 : 32, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Text("onboarding.subject.subtitle")
                .font(isPad ? .title2 : .body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)

            VStack(spacing: 8) {
                ForEach(MenuFilter.allCases) { filter in
                    Button {
                        menuFilterRaw = filter.rawValue
                        advance(to: 2)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: filter.icon)
                                .font(.system(size: isPad ? 28 : 21, weight: .bold))
                                .frame(width: isPad ? 44 : 30)
                            Text(filter.title)
                                .font(isPad ? .title2.weight(.semibold) : .title3.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, isPad ? 26 : 16)
                        .frame(maxWidth: .infinity, minHeight: isPad ? 72 : 54)
                        .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(OnboardingOptionStyle())
                    .foregroundStyle(.orange)
                }
            }
        }
    }

    private var levelStep: some View {
        VStack(spacing: 14) {
            Text("onboarding.level.title")
                .font(.system(size: isPad ? 46 : 32, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("onboarding.level.subtitle \(MenuFilter(rawValue: menuFilterRaw)?.title ?? L("onboarding.level.thisTopic"))")
                .font(isPad ? .title2 : .body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)

            Button { finish(with: .order) } label: {
                OnboardingChoiceLabel(
                    title: L("onboarding.level.beginner.title"),
                    subtitle: L("onboarding.level.beginner.subtitle"),
                    icon: "leaf.fill"
                )
            }
            .buttonStyle(OnboardingOptionStyle())

            Button { finish(with: .random) } label: {
                OnboardingChoiceLabel(
                    title: L("onboarding.level.intermediate.title"),
                    subtitle: L("onboarding.level.intermediate.subtitle"),
                    icon: "shuffle"
                )
            }
            .buttonStyle(OnboardingOptionStyle())

            Button { finish(with: .mixed) } label: {
                OnboardingChoiceLabel(
                    title: L("onboarding.level.advanced.title"),
                    subtitle: L("onboarding.level.advanced.subtitle"),
                    icon: "bolt.fill"
                )
            }
            .buttonStyle(OnboardingOptionStyle())
        }
    }

    private func goToSubjects() {
        let trimmedName = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        playerName = trimmedName.isEmpty ? "Jumping Fox" : trimmedName
        isNameFieldFocused = false
        advance(to: 1)
    }

    private func advance(to newStep: Int) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            step = newStep
        }
    }

    private func finish(with mode: PracticeMode) {
        menuModeRaw = mode.rawValue
        // The Supermix filter has no mode picker of its own — map the
        // beginner/advanced choice onto its simplest and most complete button.
        if MenuFilter(rawValue: menuFilterRaw) == .mixed {
            supermixCategoryRaw = (mode == .mixed ? ChallengeCategory.superAll : .superBasic).rawValue
        }
        withAnimation(.easeInOut(duration: 0.55)) {
            isComplete = true
        }
    }
}

private struct OnboardingButtonStyle: ButtonStyle {
    let isPad: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(isPad ? .title2.weight(.bold) : .headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, isPad ? 22 : 15)
            .background(.orange, in: Capsule())
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

private struct OnboardingOptionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.white.opacity(configuration.isPressed ? 0.52 : 0), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

private struct OnboardingChoiceLabel: View {
    let title: String
    let subtitle: String
    let icon: String
    private var isPad: Bool { AppLayout.isPad }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
            .font(isPad ? .title2 : .title3)
            .frame(width: isPad ? 44 : 30)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(isPad ? .title2.weight(.semibold) : .title3.weight(.semibold))
                Text(subtitle)
                    .font(isPad ? .title3 : .callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, isPad ? 26 : 16)
        .frame(maxWidth: .infinity, minHeight: isPad ? 94 : 70)
        .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .foregroundStyle(Color(red: 0.43, green: 0.20, blue: 0.03))
    }
}

struct CharacterPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var language = LanguageManager.shared
    @AppStorage(GameSettings.characterKey) private var characterID = "fox"
    let theme: AnimalCharacter

    var body: some View {
        NavigationStack {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 74))], spacing: 14) {
                ForEach(CharacterCatalog.all) { animal in
                    Button {
                        characterID = animal.id
                        dismiss()
                    } label: {
                        VStack(spacing: 5) {
                            animal.artwork
                                .resizable()
                                .scaledToFit()
                                .frame(width: 54, height: 54)
                            Text(animal.localizedName).font(.caption.weight(.bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(characterID == animal.id ? theme.color : .white,
                                    in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(characterID == animal.id ? .white : theme.deepColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(theme.skyColor.ignoresSafeArea())
            .navigationTitle("character.pickerTitle")
        }
    }
}
