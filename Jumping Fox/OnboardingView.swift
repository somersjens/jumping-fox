import SwiftUI

struct OnboardingView: View {
    @AppStorage(GameSettings.playerNameKey) private var playerName = ""
    @AppStorage(GameSettings.onboardingCompleteKey) private var isComplete = false
    @AppStorage("ui.menuFilter") private var menuFilterRaw = MenuFilter.tables.rawValue
    @AppStorage("ui.menuMode") private var menuModeRaw = MenuMode.standard.rawValue
    @ObservedObject private var language = LanguageManager.shared
    @State private var step = 0
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        ZStack {
            onboardingBackground

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Image("no_background")
                            .resizable()
                            .scaledToFit()
                            .frame(width: step == 1 ? 112 : 150, height: step == 1 ? 112 : 150)
                            .padding(.bottom, step == 1 ? 14 : 22)
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
                    .frame(maxWidth: 500)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 28)
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
                    .padding(.top, 8)
                    .padding(.leading, 16)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            LanguagePicker(tint: Color(red: 0.43, green: 0.20, blue: 0.03).opacity(0.6))
                .padding(.top, 8)
                .padding(.trailing, 16)
        }
    }

    private var backButton: some View {
        Button {
            advance(to: step - 1)
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(red: 0.43, green: 0.20, blue: 0.03).opacity(0.6))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
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
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)

                Text("onboarding.name.subtitle")
                    .font(.body.weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            TextField(String(), text: $playerName, prompt: Text("name.placeholder"))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .focused($isNameFieldFocused)
                .textContentType(.name)
                .submitLabel(.next)
                .onSubmit { goToSubjects() }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isNameFieldFocused ? Color.orange : .brown.opacity(0.18),
                                lineWidth: isNameFieldFocused ? 2 : 1)
                )
                .frame(maxWidth: 300)
                .animation(.snappy(duration: 0.2), value: isNameFieldFocused)

            Button("common.continue") { goToSubjects() }
                .buttonStyle(OnboardingButtonStyle())
        }
    }

    private var subjectStep: some View {
        VStack(spacing: 14) {
            Text("onboarding.subject.title")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Text("onboarding.subject.subtitle")
                .font(.subheadline)
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
                                .font(.title3)
                                .frame(width: 28)
                            Text(filter.title)
                                .font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, minHeight: 48)
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
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("onboarding.level.subtitle \(MenuFilter(rawValue: menuFilterRaw)?.title ?? L("onboarding.level.thisTopic"))")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)

            Button { finish(with: .standard) } label: {
                OnboardingChoiceLabel(
                    title: L("onboarding.level.beginner.title"),
                    subtitle: L("onboarding.level.beginner.subtitle"),
                    icon: "leaf.fill"
                )
            }
            .buttonStyle(OnboardingOptionStyle())

            Button { finish(with: .mix) } label: {
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

    private func finish(with mode: MenuMode) {
        menuModeRaw = mode.rawValue
        withAnimation(.easeInOut(duration: 0.55)) {
            isComplete = true
        }
    }
}

private struct OnboardingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
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

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.headline)
                .frame(width: 28)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 64)
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
