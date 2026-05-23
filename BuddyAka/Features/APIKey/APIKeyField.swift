import SwiftUI

struct APIKeyField: View {
    var onSave: ((Bool) -> Void)? = nil

    @State private var apiKey: String
    @State private var savedFlash: Bool = false
    @State private var errorMessage: String?

    init(onSave: ((Bool) -> Void)? = nil) {
        self.onSave = onSave
        let initial = (try? KeychainStore.get(key: GeminiAPIKey.keychainKey)) ?? nil
        _apiKey = State(initialValue: initial ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Gemini API Key")).font(.headline)
            SecureField(String(localized: "Paste your Gemini API key"), text: $apiKey)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button(String(localized: "Save"), action: save)
                    .disabled(apiKey.isEmpty)
                statusLabel
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.red)
        } else if savedFlash {
            Text(String(localized: "Saved ✓"))
                .foregroundStyle(.green)
        }
    }

    private func save() {
        do {
            try KeychainStore.set(key: GeminiAPIKey.keychainKey, value: apiKey)
            errorMessage = nil
            savedFlash = true
            onSave?(true)
            Task {
                try? await Task.sleep(for: .seconds(2))
                await MainActor.run { savedFlash = false }
            }
        } catch {
            savedFlash = false
            errorMessage = String(localized: "Couldn't save: \(String(describing: error))")
            onSave?(false)
        }
    }
}
