import SwiftUI
#if canImport(Translation)
import Translation
#endif

#if canImport(Translation)
/// Invisible helper that services batch translation requests through the
/// system's on-device Translation framework. Set `request` to an array of
/// strings; the translations (or an error) come back via the callbacks in
/// the same order.
@available(macOS 15.0, *)
struct TranslationRunner: View {
    @Binding var request: [String]?
    let targetIdentifier: String
    let onResult: ([String]) -> Void
    let onError: (String) -> Void

    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: request) { trigger() }
            .onAppear { trigger() }
            .translationTask(configuration) { session in
                guard let texts = request else { return }
                do {
                    let requests = texts.enumerated().map { index, text in
                        TranslationSession.Request(sourceText: text, clientIdentifier: "\(index)")
                    }
                    let responses = try await session.translations(from: requests)
                    var results = texts
                    for response in responses {
                        if let id = response.clientIdentifier, let index = Int(id),
                           results.indices.contains(index) {
                            results[index] = response.targetText
                        }
                    }
                    onResult(results)
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
