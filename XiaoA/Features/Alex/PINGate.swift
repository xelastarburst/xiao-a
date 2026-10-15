import SwiftUI

/// Long-press 小A on the home screen to get here. Keeps settings away from Mom.
struct PINGate: View {
    var onUnlock: () -> Void

    @EnvironmentObject private var store: ConfigStore
    @Environment(\.dismiss) private var dismiss
    @State private var entry = ""
    @State private var wrong = false

    var body: some View {
        NavigationStack {
            Form {
                if store.config.pin.isEmpty {
                    Section {
                        Text("No PIN yet. Set one inside Alex mode so Mom can't change settings by accident.")
                    }
                    Button("Open Alex mode", action: unlock)
                } else {
                    Section {
                        SecureField("PIN", text: $entry)
                            .keyboardType(.numberPad)
                            .onSubmit(check)
                        if wrong {
                            Text("Wrong PIN").foregroundStyle(.red)
                        }
                    }
                    Button("Unlock", action: check)
                }
            }
            .navigationTitle("Alex mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func check() {
        if entry == store.config.pin {
            unlock()
        } else {
            wrong = true
            entry = ""
            Haptics.warning()
        }
    }

    private func unlock() {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onUnlock() }
    }
}
