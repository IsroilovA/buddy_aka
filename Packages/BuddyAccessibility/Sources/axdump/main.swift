import AppKit
import BuddyAccessibility
import BuddyUIModel
import Darwin
import Foundation

@MainActor
struct CLI {
    enum ExitCode: Int32 {
        case ok = 0
        case argError = 1
        case axPermission = 2
        case targetNotFound = 3
        case extractorError = 4
    }

    static func usage() -> String {
        """
        Usage: axdump [target] [options]

        Target (default --frontmost):
          --frontmost
          --pid <pid>
          --bundle <bundle-id>

        Options:
          --whole-app             Dump whole app tree, not just focused window
          --no-onscreen-filter    Include off-screen elements
          --pretty                Pretty-print JSON
          --output <path>         Write JSON to file (default stdout)
          --timeout-ms <int>      Overall wallclock cap in ms (default 1000)
          --watch [seconds]       After the dump, print AX events for N seconds (default 30)
          -h, --help              Show this help

        Env:
          BUDDY_AX_DEBUG=1        Verbose stderr trace
        """
    }

    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        var target: AXTarget = .frontmost
        var options = AXExtractOptions()
        var pretty = false
        var outputPath: String?
        var watchSeconds: Int?

        func popValue(for flag: String) -> String? {
            guard !args.isEmpty else {
                FileHandle.standardError.write(Data("axdump: \(flag) requires a value\n".utf8))
                return nil
            }
            return args.removeFirst()
        }

        while !args.isEmpty {
            let arg = args.removeFirst()
            switch arg {
            case "-h", "--help":
                print(usage())
                exit(ExitCode.ok.rawValue)
            case "--frontmost":
                target = .frontmost
            case "--pid":
                guard let v = popValue(for: arg), let pid = pid_t(v) else {
                    exit(ExitCode.argError.rawValue)
                }
                target = .pid(pid)
            case "--bundle":
                guard let v = popValue(for: arg) else { exit(ExitCode.argError.rawValue) }
                target = .bundleID(v)
            case "--whole-app":
                options.windowOnly = false
            case "--no-onscreen-filter":
                options.onScreenOnly = false
            case "--pretty":
                pretty = true
            case "--output":
                guard let v = popValue(for: arg) else { exit(ExitCode.argError.rawValue) }
                outputPath = v
            case "--timeout-ms":
                guard let v = popValue(for: arg), let n = Int(v) else {
                    exit(ExitCode.argError.rawValue)
                }
                options.overallTimeoutMs = n
            case "--watch":
                // Optional positional value; default 30s. If the next token is
                // an integer, consume it; otherwise leave it for the next loop.
                if let v = args.first, let n = Int(v), n > 0 {
                    args.removeFirst()
                    watchSeconds = n
                } else {
                    watchSeconds = 30
                }
            default:
                FileHandle.standardError.write(Data("axdump: unknown argument: \(arg)\n\n".utf8))
                FileHandle.standardError.write(Data(usage().utf8))
                exit(ExitCode.argError.rawValue)
            }
        }

        let extractor = AXExtractor()
        let snapshot: UISnapshot
        do {
            let result = try await extractor.extract(target: target, options: options)
            snapshot = result.snapshot
        } catch AXExtractor.Error.accessibilityNotTrusted {
            FileHandle.standardError.write(Data(
                "axdump: Accessibility permission missing.\nGrant your terminal (Terminal / iTerm / Ghostty / etc.) Accessibility in:\n  System Settings → Privacy & Security → Accessibility\n".utf8
            ))
            exit(ExitCode.axPermission.rawValue)
        } catch AXExtractor.Error.appNotFound(let t) {
            FileHandle.standardError.write(Data("axdump: target not found: \(t)\n".utf8))
            exit(ExitCode.targetNotFound.rawValue)
        } catch AXExtractor.Error.noFocusedWindow {
            FileHandle.standardError.write(Data("axdump: target has no focused window (try --whole-app)\n".utf8))
            exit(ExitCode.extractorError.rawValue)
        } catch {
            FileHandle.standardError.write(Data("axdump: \(error)\n".utf8))
            exit(ExitCode.extractorError.rawValue)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty
            ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            : [.withoutEscapingSlashes]
        let data: Data
        do {
            data = try encoder.encode(snapshot)
        } catch {
            FileHandle.standardError.write(Data("axdump: encode failed: \(error)\n".utf8))
            exit(ExitCode.extractorError.rawValue)
        }

        if let outputPath {
            do {
                try data.write(to: URL(fileURLWithPath: outputPath))
            } catch {
                FileHandle.standardError.write(Data("axdump: write failed: \(error)\n".utf8))
                exit(ExitCode.extractorError.rawValue)
            }
        } else {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }

        if ProcessInfo.processInfo.environment["BUDDY_AX_DEBUG"] == "1" {
            let s = snapshot.stats
            FileHandle.standardError.write(Data(
                "axdump: scanned=\(s.scanned) kept=\(s.kept) truncated=\(s.truncated) elapsed=\(s.elapsedMs)ms\n".utf8
            ))
        }

        if let watchSeconds {
            await watch(target: target, seconds: watchSeconds)
        }

        exit(ExitCode.ok.rawValue)
    }

    private static func watch(target: AXTarget, seconds: Int) async {
        let pid: pid_t
        switch resolvePID(target) {
        case .ok(let p): pid = p
        case .fail(let code):
            exit(code.rawValue)
        }

        let stream: AXEventStream
        do {
            stream = try AXEventStream(initialPid: pid)
        } catch AXEventStream.Error.accessibilityNotTrusted {
            FileHandle.standardError.write(Data("axdump: AX permission revoked between dump and watch\n".utf8))
            exit(ExitCode.axPermission.rawValue)
        } catch {
            FileHandle.standardError.write(Data("axdump: AXEventStream init failed: \(error)\n".utf8))
            exit(ExitCode.extractorError.rawValue)
        }

        FileHandle.standardError.write(Data("axdump: watching pid \(pid) for \(seconds)s — Ctrl-C to stop\n".utf8))

        let consumer = Task { @MainActor in
            for await event in stream.events {
                let line = format(event: event) + "\n"
                FileHandle.standardOutput.write(Data(line.utf8))
            }
        }

        try? await Task.sleep(for: .seconds(seconds))
        stream.stop()
        _ = await consumer.value
    }

    private enum PIDResult {
        case ok(pid_t)
        case fail(ExitCode)
    }

    private static func resolvePID(_ target: AXTarget) -> PIDResult {
        switch target {
        case .frontmost:
            guard let app = NSWorkspace.shared.frontmostApplication else {
                FileHandle.standardError.write(Data("axdump: no frontmost app\n".utf8))
                return .fail(.targetNotFound)
            }
            return .ok(app.processIdentifier)
        case .pid(let pid):
            return .ok(pid)
        case .bundleID(let id):
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first else {
                FileHandle.standardError.write(Data("axdump: bundle not running: \(id)\n".utf8))
                return .fail(.targetNotFound)
            }
            return .ok(app.processIdentifier)
        }
    }

    private static let isoFormatter = ISO8601DateFormatter()

    private static func format(event: AXEvent) -> String {
        let ts = Self.isoFormatter.string(from: Date())
        switch event {
        case .focusedElementChanged: return "\(ts) focused_element_changed"
        case .focusedWindowChanged:  return "\(ts) focused_window_changed"
        case .layoutChanged:         return "\(ts) layout_changed"
        case .valueChanged:          return "\(ts) value_changed"
        case .windowCreated:         return "\(ts) window_created"
        case .elementDestroyed:      return "\(ts) element_destroyed"
        case .menuOpened:            return "\(ts) menu_opened"
        case .menuClosed:            return "\(ts) menu_closed"
        }
    }
}

await CLI.main()
