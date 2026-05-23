import AVFoundation
import ApplicationServices
import AppKit
import CoreGraphics
import Observation

@MainActor
@Observable
final class PermissionsCoordinator {
    private(set) var accessibility: PermissionStatus = .notDetermined
    private(set) var screenCapture: PermissionStatus = .notDetermined
    private(set) var microphone: PermissionStatus = .notDetermined

    // Kinds we've prompted for this launch. The OS won't re-prompt for AX/Screen
    // after the first attempt, and the underlying APIs never expose a distinct
    // "denied" state — so once we've attempted and the API still reports false,
    // the only honest mapping is .denied.
    private var attempted: Set<PermissionKind> = []

    // In-flight prompts (mic is async; suppresses double-fire on rapid clicks).
    private var pending: Set<PermissionKind> = []

    // NotificationCenter token removal is thread-safe; mark nonisolated(unsafe)
    // so the deinit (nonisolated on @MainActor classes) can clean up.
    // @ObservationIgnored avoids the @Observable macro generating MainActor-isolated accessors.
    @ObservationIgnored private nonisolated(unsafe) var activeObserver: NSObjectProtocol?

    init() {
        refresh()
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // `forName:queue:.main` delivers on the main thread, but the closure
            // type is non-isolated — hop to the actor explicitly.
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    deinit {
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
    }

    var allGranted: Bool {
        accessibility == .granted && screenCapture == .granted && microphone == .granted
    }

    var missing: [PermissionKind] {
        PermissionKind.allCases.filter { status(of: $0) != .granted }
    }

    func status(of kind: PermissionKind) -> PermissionStatus {
        switch kind {
        case .accessibility: return accessibility
        case .screenCapture: return screenCapture
        case .microphone:    return microphone
        }
    }

    func rows(filter: PermissionsList.Filter) -> [PermissionRowModel] {
        let kinds: [PermissionKind]
        switch filter {
        case .all:         kinds = PermissionKind.allCases
        case .missingOnly: kinds = missing
        }
        return kinds.map { kind in
            PermissionRowModel(
                kind: kind,
                title: kind.title,
                subtitle: kind.subtitle,
                status: status(of: kind),
                url: kind.systemSettingsURL,
                grant: { [weak self] in self?.request(kind) }
            )
        }
    }

    func refresh() {
        accessibility = mapBoolAPI(AXIsProcessTrusted(), kind: .accessibility)
        screenCapture = mapBoolAPI(CGPreflightScreenCaptureAccess(), kind: .screenCapture)
        microphone    = mapMic(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    func request(_ kind: PermissionKind) {
        guard !pending.contains(kind) else { return }

        let shouldDeepLink: Bool
        switch kind {
        case .microphone:
            shouldDeepLink = (microphone == .denied)
        case .accessibility, .screenCapture:
            shouldDeepLink = attempted.contains(kind) && status(of: kind) != .granted
        }
        if shouldDeepLink {
            openSystemSettings(for: kind)
            return
        }

        attempted.insert(kind)
        pending.insert(kind)
        switch kind {
        case .accessibility:
            requestAccessibility()
            pending.remove(kind)
        case .screenCapture:
            requestScreenCapture()
            pending.remove(kind)
        case .microphone:
            Task { @MainActor [weak self] in
                _ = await AVCaptureDevice.requestAccess(for: .audio)
                guard let self else { return }
                self.refresh()
                self.reactivate()
                self.pending.remove(.microphone)
            }
        }
    }

    private func requestAccessibility() {
        // Prompt option triggers the system dialog and adds the app to the Privacy list.
        let opts: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(opts)
        refresh()
        reactivate()
    }

    private func requestScreenCapture() {
        _ = CGRequestScreenCaptureAccess()
        refresh()
        reactivate()
    }

    // After an OS modal prompt, an LSUIElement app loses focus to whichever
    // regular app was previously active. Pull focus back so our window stays in view.
    private func reactivate() {
        DispatchQueue.main.async { NSApp.activate() }
    }

    private func openSystemSettings(for kind: PermissionKind) {
        guard let url = URL(string: kind.systemSettingsURL),
              NSWorkspace.shared.open(url) else {
            NSLog("BuddyAka: failed to open System Settings URL for \(kind)")
            return
        }
    }

    private func mapBoolAPI(_ granted: Bool, kind: PermissionKind) -> PermissionStatus {
        if granted { return .granted }
        return attempted.contains(kind) ? .denied : .notDetermined
    }

    private func mapMic(_ s: AVAuthorizationStatus) -> PermissionStatus {
        switch s {
        case .authorized:        return .granted
        case .denied, .restricted: return .denied
        case .notDetermined:     return .notDetermined
        @unknown default:        return .notDetermined
        }
    }
}
