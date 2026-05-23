import AppKit
import BuddyAccessibility
import BuddyUIModel
import KeyboardShortcuts
import Observation

extension KeyboardShortcuts.Name {
    static let demoStep = Self("demoStep",
        default: .init(.n, modifiers: [.command, .shift]))
}

private let interactableRoles: Set<UIElementRole> = [
    .button, .link, .textField, .checkbox, .radio, .tab,
    .menuItem, .option, .switchControl, .combobox, .searchbox, .slider,
]

@MainActor
@Observable
final class DemoCursorAnimator {
    private let overlay: OverlayState
    private(set) var active = false

    @ObservationIgnored private let extractor = AXExtractor()
    @ObservationIgnored private var monitor: Any?

    init(overlay: OverlayState) {
        self.overlay = overlay
    }

    func toggle() {
        if active {
            stop()
        } else {
            start()
        }
    }

    private func start() {
        active = true
        overlay.show()

        monitor = KeyboardShortcuts.onKeyDown(for: .demoStep) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.stepToRandomElement()
            }
        }
    }

    func stop() {
        active = false
        KeyboardShortcuts.disable(.demoStep)
        monitor = nil
        overlay.hide()
    }

    private func stepToRandomElement() async {
        guard active else { return }

        do {
            let (snapshot, resolver) = try await extractor.extract(
                target: .frontmost,
                options: AXExtractOptions(windowOnly: true, onScreenOnly: true)
            )

            let candidates = snapshot.elements.filter { node in
                interactableRoles.contains(node.role)
                    && node.enabled
                    && node.frame.w > 4
                    && node.frame.h > 4
            }

            guard let pick = candidates.randomElement() else { return }

            if let liveRect = resolver.liveFrame(for: pick.id) {
                let cocoa = ScreenGeometry.axRectToCocoa(liveRect)
                overlay.pointAt(cocoa)
            } else {
                let cocoa = ScreenGeometry.axRectToCocoa(pick.frame.cgRect)
                overlay.pointAt(cocoa)
            }
        } catch {
            NSLog("DemoCursorAnimator: extraction failed – %@", String(describing: error))
        }
    }
}
