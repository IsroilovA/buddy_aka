import BuddyVoice
import SwiftUI

struct VoiceRow: View {
    let voice: PrebuiltVoice
    let isSelected: Bool
    let isAuditioning: Bool
    let canAudition: Bool
    let onSelect: () -> Void
    let onAudition: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .font(.title3)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: voice.id)
                            .font(.body)
                        Text(localizedDescriptor)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])

            Button(action: onAudition) {
                Image(systemName: isAuditioning ? "stop.circle.fill" : "play.circle")
                    .font(.title2)
                    .foregroundStyle(canAudition ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!canAudition)
            .help(canAudition
                  ? (isAuditioning ? String(localized: "Stop sample") : String(localized: "Play sample"))
                  : String(localized: "Set your API key in the API Key tab to audition voices."))
            .accessibilityLabel(isAuditioning
                                ? String(localized: "Stop sample")
                                : String(localized: "Play sample"))
        }
        .padding(.vertical, 2)
    }

    private var localizedDescriptor: String {
        // String(localized:) needs a string literal at the call site to extract; the
        // descriptors are a closed set so a small switch keeps the catalog happy.
        switch voice.descriptor {
        case "Upbeat":      return String(localized: "Upbeat")
        case "Informative": return String(localized: "Informative")
        case "Excitable":   return String(localized: "Excitable")
        case "Breezy":      return String(localized: "Breezy")
        case "Youthful":    return String(localized: "Youthful")
        case "Bright":      return String(localized: "Bright")
        default:            return voice.descriptor
        }
    }
}
