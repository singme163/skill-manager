import SwiftUI
#if canImport(Translation)
import Translation
#endif

#if canImport(Translation)
/// Invisible helper that services one-off translation requests through the
/// system's on-device Translation framework. Set `request` to a string to
/// translate it; the result (or error) comes back via the callbacks.
@available(macOS 15.0, *)
struct TranslationRunner: View {
    @Binding var request: String?
    let targetIdentifier: String
    let onResult: (String) -> Void
    let onError: (String) -> Void

    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: request) { trigger() }
            .onAppear { trigger() }
            .translationTask(configuration) { session in
                guard let text = request else { return }
                do {
                    let response = try await session.translate(text)
                    onResult(response.targetText)
                } catch {
                    onError(error.localizedDescription)
                }
                request = nil
            }
    }

    private func trigger() {
        guard request != nil else { return }
        if configuration == nil {
            configuration = TranslationSession.Configuration(
                target: Locale.Language(identifier: targetIdentifier)
            )
        } else {
            configuration?.invalidate()
        }
    }
}
#endif
