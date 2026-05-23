import SwiftUI

struct PermissionRow: View {
    let title: String
    let subtitle: String?
    let status: PermissionStatus
    let systemSettingsURL: String
    let grant: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            statusGlyph
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                statusLabel
            }

            Spacer()

            Button(String(localized: "Grant"), action: grant)
                .buttonStyle(.borderedProminent)
                .disabled(status == .granted)

            Button {
                guard let url = URL(string: systemSettingsURL),
                      NSWorkspace.shared.open(url) else {
                    NSLog("BuddyAka: failed to open System Settings URL: \(systemSettingsURL)")
                    return
                }
            } label: {
                Image(systemName: "gear")
            }
            .buttonStyle(.bordered)
            .help(String(localized: "Open System Settings"))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    @ViewBuilder
    private var statusGlyph: some View {
        switch status {
        case .granted:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .denied:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .notDetermined:
            Image(systemName: "circle.dashed").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch status {
        case .granted:
            Text(String(localized: "Granted")).font(.caption).foregroundStyle(.green)
        case .denied:
            Text(String(localized: "Denied")).font(.caption).foregroundStyle(.red)
        case .notDetermined:
            Text(String(localized: "Not determined")).font(.caption).foregroundStyle(.secondary)
        }
    }
}
