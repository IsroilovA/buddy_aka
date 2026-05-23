import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class TargetApplicationTracker {
    private(set) var currentApplication: NSRunningApplication?

    @ObservationIgnored private let ownBundleID = Bundle.main.bundleIdentifier
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private let continuation: AsyncStream<pid_t>.Continuation
    @ObservationIgnored let targetChanges: AsyncStream<pid_t>

    init(workspace: NSWorkspace = .shared) {
        let (stream, cont) = AsyncStream<pid_t>.makeStream(bufferingPolicy: .bufferingNewest(16))
        self.targetChanges = stream
        self.continuation = cont

        if let app = workspace.frontmostApplication, Self.isCandidate(app, ownBundleID: ownBundleID) {
            currentApplication = app
            cont.yield(app.processIdentifier)
        }

        observer = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            Task { @MainActor [weak self] in
                self?.recordActivatedApplication(app)
            }
        }
    }

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        continuation.finish()
    }

    var currentPID: pid_t? {
        currentApplication?.processIdentifier
    }

    var currentBundleID: String? {
        currentApplication?.bundleIdentifier
    }

    func recordActivatedApplication(_ app: NSRunningApplication) {
        guard Self.isCandidate(app, ownBundleID: ownBundleID) else { return }
        guard app.processIdentifier != currentApplication?.processIdentifier else { return }
        currentApplication = app
        continuation.yield(app.processIdentifier)
    }

    private static func isCandidate(_ app: NSRunningApplication, ownBundleID: String?) -> Bool {
        guard !app.isTerminated else { return false }
        if let ownBundleID, app.bundleIdentifier == ownBundleID { return false }
        return app.activationPolicy == .regular || app.activationPolicy == .accessory
    }
}
