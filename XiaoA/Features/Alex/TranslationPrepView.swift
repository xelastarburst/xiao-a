import SwiftUI
import Translation

/// Downloads Apple's on-device English → German pack so Lesen works with no data.
struct TranslationPrepView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var configuration: TranslationSession.Configuration?
    @State private var status = "Checking…"
    @State private var ready = false

    private let english = Locale.Language(identifier: "en")
    private let german = Locale.Language(identifier: "de")

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: ready ? "checkmark.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 64))
                    .foregroundStyle(ready ? .green : Palette.teal)
                Text(status).multilineTextAlignment(.center)
                if !ready {
                    Button("Download") {
                        configuration = TranslationSession.Configuration(source: english, target: german)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(32)
            .translationTask(configuration) { session in
                do {
                    try await session.prepareTranslation()
                    status = "Ready. Live camera translation now works offline."
                    ready = true
                } catch {
                    status = "Couldn't download: \(error.localizedDescription)"
                }
            }
            .task {
                let availability = LanguageAvailability()
                let result = await availability.status(from: english, to: german)
                switch result {
                case .installed:
                    status = "Already downloaded. Lesen works offline."
                    ready = true
                case .supported:
                    status = "Tap Download. iOS will ask to download English and German."
                default:
                    status = "This iPhone can't translate English to German on-device."
                }
            }
            .navigationTitle("Offline translation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
