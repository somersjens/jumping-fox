#if TRAILER_EXPORT
import SwiftUI
import Combine

@MainActor
final class PremiumPromoTourCoordinator: ObservableObject {
    static let shared = PremiumPromoTourCoordinator()

    struct LanguageScrollRequest: Equatable {
        enum Anchor: Equatable { case top, center, bottom }

        let id = UUID()
        let code: String
        let duration: Double
        let anchor: Anchor

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    }

    @Published var isPremiumPresented = false
    @Published private(set) var previewCharacterID = CharacterCatalog.freeCharacterID
    @Published private(set) var isLanguagePickerPresented = false
    @Published private(set) var languagePickerInitialCode = AppLanguage.all.first?.code ?? "en"
    @Published private(set) var languageScrollRequest: LanguageScrollRequest?
    @Published private(set) var presentationGeneration = 0

    private var preparedRecorder = false
    private var startedTour = false
    private var tourTask: Task<Void, Never>?

    private init() {}

    func reset() {
        tourTask?.cancel()
        tourTask = nil
        preparedRecorder = false
        startedTour = false
        previewCharacterID = CharacterCatalog.freeCharacterID
        isLanguagePickerPresented = false
        languagePickerInitialCode = AppLanguage.all.first?.code ?? "en"
        languageScrollRequest = nil
        presentationGeneration = 0
        isPremiumPresented = false

        DispatchQueue.main.async { [weak self] in
            self?.isPremiumPresented = true
        }
    }

    func premiumViewDidAppear() {
        guard !preparedRecorder else { return }
        preparedRecorder = true

        // Let the initial sheet animation and its first layout finish before
        // the capture script receives the ready signal.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            let recorder = PromoTrailerRecorder.shared
            recorder.prepare()
            recorder.waitForStart { [weak self] in self?.beginTour() }
        }
    }

    func setLanguagePickerPresented(_ presented: Bool, initialCode: String) {
        languagePickerInitialCode = initialCode
        withAnimation(.easeInOut(duration: 0.24)) {
            isLanguagePickerPresented = presented
        }
    }

    func selectLanguage(code: String) {
        guard let option = AppLanguage.named(code) else { return }
        withAnimation(.easeInOut(duration: 0.24)) {
            isLanguagePickerPresented = false
        }
        LanguageManager.shared.select(option)
    }

    private func beginTour() {
        guard !startedTour else { return }
        startedTour = true
        tourTask = Task { @MainActor [weak self] in
            await self?.runTour()
        }
    }

    private func wait(milliseconds: Int) async -> Bool {
        do {
            try await Task.sleep(for: .milliseconds(milliseconds))
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    private func showCharacter(_ id: String) {
        AppAudio.shared.playMenuTap()
        withAnimation(.easeInOut(duration: 0.30)) {
            previewCharacterID = id
        }
        PromoTrailerRecorder.shared.event("premium_character_\(id)")
    }

    private func requestLanguageScroll(code: String,
                                       duration: Double,
                                       anchor: LanguageScrollRequest.Anchor) {
        languageScrollRequest = LanguageScrollRequest(
            code: code,
            duration: duration,
            anchor: anchor
        )
    }

    private func runTour() async {
        let recorder = PromoTrailerRecorder.shared

        guard await wait(milliseconds: 900) else { return }
        for animal in CharacterCatalog.all.dropFirst() {
            showCharacter(animal.id)
            guard await wait(milliseconds: 1_050) else { return }
        }
        showCharacter(CharacterCatalog.freeCharacterID)
        guard await wait(milliseconds: 650) else { return }

        AppAudio.shared.playMenuTap()
        setLanguagePickerPresented(true, initialCode: AppLanguage.all.first?.code ?? "en")
        recorder.event("premium_language_picker_open_top")
        guard await wait(milliseconds: 450) else { return }

        // Travel directly from the top of the list to Arabic. The previous
        // bottom-and-back route added motion without helping the story; this
        // keeps the same calm linear scrolling speed with Arabic as its only
        // destination.
        requestLanguageScroll(code: "ar", duration: 1.8, anchor: .center)
        recorder.event("premium_language_scroll_arabic")
        guard await wait(milliseconds: 2_150) else { return }

        AppAudio.shared.playMenuTap()
        selectLanguage(code: "ar")
        recorder.event("premium_language_arabic")
        // Let the picker's close transition complete, then hold the fully
        // mirrored Premium screen for a clean full second.
        guard await wait(milliseconds: 1_300) else { return }

        AppAudio.shared.playMenuTap()
        isPremiumPresented = false
        recorder.event("premium_sheet_closed")
        guard await wait(milliseconds: 1_050) else { return }

        presentationGeneration += 1
        isPremiumPresented = true
        recorder.event("premium_sheet_reopened")
        guard await wait(milliseconds: 1_350) else { return }

        AppAudio.shared.playMenuTap()
        setLanguagePickerPresented(true, initialCode: "ar")
        recorder.event("premium_language_picker_open_arabic")
        guard await wait(milliseconds: 450) else { return }

        requestLanguageScroll(code: "en", duration: 0.85, anchor: .center)
        recorder.event("premium_language_scroll_english")
        guard await wait(milliseconds: 1_200) else { return }

        AppAudio.shared.playMenuTap()
        selectLanguage(code: "en")
        recorder.event("premium_language_english")
        guard await wait(milliseconds: 1_150) else { return }

        recorder.finish(eventName: "premium_loop_complete")
    }
}

struct PremiumPromoTourView: View {
    @ObservedObject private var language = LanguageManager.shared
    @StateObject private var coordinator = PremiumPromoTourCoordinator.shared

    var body: some View {
        ContentView(promoPremiumBackdrop: true)
            .sheet(
                isPresented: Binding(
                    get: { coordinator.isPremiumPresented },
                    set: { coordinator.isPremiumPresented = $0 }
                )
            ) {
                PremiumView(
                    initialCharacterID: coordinator.previewCharacterID,
                    promoTour: true
                )
                .id(coordinator.presentationGeneration)
                .premiumSheetPresentation()
                .interactiveDismissDisabled()
            }
            .onAppear { coordinator.reset() }
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.layoutDirection)
            .preferredColorScheme(.light)
    }
}

struct PromoLanguagePickerPanel: View {
    let tint: Color
    @ObservedObject var coordinator: PremiumPromoTourCoordinator
    @ObservedObject private var language = LanguageManager.shared

    private var isPad: Bool { AppLayout.isPad }

    var body: some View {
        GeometryReader { geometry in
            let width = min(isPad ? 470 : 350, geometry.size.width - 32)
            let height = min(isPad ? 720 : 610, geometry.size.height - (isPad ? 150 : 130))

            ZStack(alignment: .topTrailing) {
                Color.black.opacity(0.025)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack {
                        Text("language.select")
                            .font(.system(size: isPad ? 22 : 17, weight: .heavy, design: .rounded))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.up")
                            .font(.system(size: isPad ? 15 : 12, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, isPad ? 20 : 16)
                    .frame(height: isPad ? 58 : 48)

                    Divider().overlay(.white.opacity(0.54))

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(AppLanguage.all) { option in
                                    Button {
                                        coordinator.selectLanguage(code: option.code)
                                    } label: {
                                        HStack(spacing: isPad ? 14 : 11) {
                                            Text(option.flag)
                                                .font(.system(size: isPad ? 26 : 22))
                                            Text(verbatim: option.displayName)
                                                .font(.system(size: isPad ? 20 : 16, weight: .semibold))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                            Spacer(minLength: 8)
                                            if language.effective.code == option.code {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: isPad ? 17 : 14, weight: .bold))
                                                    .foregroundStyle(tint)
                                            }
                                        }
                                        .padding(.horizontal, isPad ? 20 : 16)
                                        .frame(height: isPad ? 55 : 46)
                                        .background {
                                            if language.effective.code == option.code {
                                                RoundedRectangle(cornerRadius: isPad ? 16 : 13,
                                                                 style: .continuous)
                                                    .fill(tint.opacity(0.12))
                                                    .padding(.horizontal, isPad ? 8 : 6)
                                                    .padding(.vertical, 3)
                                            }
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .id(option.code)

                                    if option.id != AppLanguage.all.last?.id {
                                        Divider()
                                            .overlay(.white.opacity(0.38))
                                            .padding(.leading, isPad ? 60 : 50)
                                    }
                                }
                            }
                        }
                        .scrollIndicators(.visible)
                        .onAppear {
                            proxy.scrollTo(coordinator.languagePickerInitialCode, anchor: .top)
                        }
                        .onChange(of: coordinator.languageScrollRequest) { request in
                            guard let request else { return }
                            let anchor: UnitPoint
                            switch request.anchor {
                            case .top: anchor = .top
                            case .center: anchor = .center
                            case .bottom: anchor = .bottom
                            }
                            withAnimation(.linear(duration: request.duration)) {
                                proxy.scrollTo(request.code, anchor: anchor)
                            }
                        }
                    }
                }
                .frame(width: width, height: height)
                .modifier(PromoLiquidGlassPanel(tint: tint, isPad: isPad))
                .padding(.top, isPad ? 88 : 74)
                .padding(.trailing, 16)
            }
        }
    }
}

private struct PromoLiquidGlassPanel: ViewModifier {
    let tint: Color
    let isPad: Bool

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: isPad ? 30 : 26, style: .continuous)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .background(.ultraThinMaterial, in: shape)
                .glassEffect(in: shape)
                .overlay(shape.stroke(.white.opacity(0.72), lineWidth: 0.9))
                .shadow(color: .black.opacity(0.16), radius: 30, y: 14)
                .shadow(color: tint.opacity(0.10), radius: 10, y: 3)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.72), lineWidth: 0.9))
                .shadow(color: .black.opacity(0.16), radius: 30, y: 14)
                .shadow(color: tint.opacity(0.10), radius: 10, y: 3)
        }
    }
}
#endif
