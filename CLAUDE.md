# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Source-of-truth specs (read first)

Before any non-trivial change, read these. They contain locked decisions — do not re-litigate them:

- `specifications.md` — product spec; hero demo is Soliq.uz tax cabinet in Safari with trilingual UZ/RU/EN narration.
- `architecture.md` — tech stack (§1), permissions (§2), module layout (§3), SwiftPM dep policy (§4), build order (§11). The build order is the work plan; check it to know where the project stands.
- `flow-schema.md` — curated flow JSON schema used by `Resources/Flows/**`.

When asked to do something that contradicts these, surface the conflict before acting.

## Build / run

```
xcodebuild -project BuddyAka.xcodeproj -scheme BuddyAka -destination "platform=macOS" build
```

There are no tests. There is no linter wired yet (architecture.md §4 calls for SwiftLint — not added).

Running the built app from Xcode (`⌘R`) opens **no window** by design — it's a menu-bar app (`LSUIElement = YES`). Look for the ✨ icon in the right side of the menu bar.

To test locales: launch with `-AppleLanguages '(ru)'` / `'(uz)'`.

To reset onboarding state during testing: `defaults delete dev.alisher.BuddyAka`.

## Xcode project specifics

The project uses **`PBXFileSystemSynchronizedRootGroup`** (Xcode 16 synchronized folders). Any `.swift` / `.xcstrings` file placed anywhere under `BuddyAka/BuddyAka/**` is automatically picked up by the target — **never edit `project.pbxproj` to add files, and never tell the user to drag files into Xcode**. Moving and renaming files is free for the same reason.

Signing is via a free Apple ID "Personal Team" Apple Development cert, auto-managed, bundle ID `dev.alisher.BuddyAka`. The Designated Requirement is stable across rebuilds so TCC (Accessibility / Screen Recording / Microphone) grants persist — don't suggest changing signing config.

The app is **not sandboxed**; do not enable App Sandbox (Accessibility + Screen Recording APIs are incompatible with it). The microphone entitlement `com.apple.security.device.audio-input = YES` lives in `BuddyAka/BuddyAka.entitlements` so TCC registers the mic request.

There is **no `Info.plist` file** in the source tree. The effective `Info.plist` is generated entirely from `INFOPLIST_KEY_*` build settings (`GENERATE_INFOPLIST_FILE = YES`). `LSUIElement = YES` and `NSMicrophoneUsageDescription` are set there. To add a plist key, set the corresponding `INFOPLIST_KEY_…` in the target's Build Settings — do not create an `Info.plist` file.

## Architecture in one screen

The app is one SwiftUI `App` with three scenes:

- `Window("BuddyAka", id: "main")` — the only user-facing window. Its root is `MainWindow`, which **branches on `OnboardingState.route`** (`.wizard` / `.home` / `.blocked`). One window, one nav model, no sheets.
- `MenuBarExtra` — always present; label icon dynamically swaps based on `PermissionsCoordinator.allGranted` (subtle warning dot when blocked).
- `Settings` — `⌘,` Settings scene with Permissions + API Key tabs.

A minimal `AppDelegate` exists **solely** for `applicationShouldHandleReopen`, which re-opens the main window when the user clicks the .app in /Applications or Finder while the menu-bar agent is already running. Don't grow it without reason — SwiftUI handles everything else.

### State containers

Both containers are `@MainActor @Observable` (the modern macOS 14+ pattern — no `ObservableObject` / `@Published` / `@StateObject` / `.environmentObject` anywhere). They are owned by `BuddyAkaApp` as `@State` and injected via `.environment(value)`; consumers read them with `@Environment(Type.self)`.

- `PermissionsCoordinator` — single source of truth for the three TCC permissions. Exposes `allGranted`, `missing: [PermissionKind]`, and a `rows(filter:)` helper that returns view models. Auto-refreshes on `NSApplication.didBecomeActiveNotification`, so revoking a permission in System Settings flips the UI the moment the user returns to the app. Tracks an internal `attempted` set so that AX / ScreenCapture — which never expose a distinct "denied" state via their underlying APIs — render as **Denied** (not "Not Determined") after the user has been prompted at least once.
- `OnboardingState` — `route`, `currentStep`, and a `hasCompletedOnboarding` flag persisted via `UserDefaults` in a `didSet` (no `@AppStorage`). Initial `route` is resolved in `init()`, so window re-open never resets the wizard mid-flow. The route is the routing primitive; mutate it to navigate (`blockForPermissions()`, `returnToHome()`, `replay()`, `finishWizard()`).

### Folder layout (feature-first)

```
BuddyAka/
  App/                       // App entry, scenes, menu bar, cross-cutting runtime
    BuddyAkaApp.swift
    AppDelegate.swift
    MainWindow.swift
    Menu/                    // BuddyMenu, MenuBarLabel
    Session/                 // SessionCoordinator, GuidanceSignalController,
                             //   TargetApplicationTracker, ToolDispatcher,
                             //   Input/MouseClickSignalSource, …
  Features/                  // one folder per user-visible surface
    Onboarding/              // OnboardingState, WizardView, OnboardingView (Settings tab)
    Home/                    // HomeView
    Permissions/             // PermissionsCoordinator, PermissionKind, PermissionsList, PermissionRow, PermissionsBlockedView
    APIKey/                  // APIKeyField, APIKeySettingsView
    Overlay/                 // OverlayState, OverlayController, halo/cursor views
    BuddySettings/           // BuddySettings @Observable, settings panel
  Core/                      // cross-cutting infra, no UI
    Keychain/                // KeychainStore (throws), KeychainError
  Resources/                 // Localizable.xcstrings, Flows/
```

Rules of placement:

- `App/` — app entry, scenes, the route switcher, AppDelegate, menu-bar plumbing, **and cross-cutting runtime orchestration** (today: `Session/`, which wires Overlay + Voice + AX + mouse + target tracker but owns no view of its own). The test: if a file has no SwiftUI surface and isn't owned by a single Feature, it belongs in `App/` (or in `Core/`/`Packages/` if it's pure infra).
- `Features/<Feature>/` — every file a feature owns: its `@Observable` state container, its views, its feature-private components. Feature folders should not reach into each other; if two features need to share UI, lift it to a `Core/UI/` folder.
- `Core/<Subsystem>/` — cross-cutting *pure-Swift* infrastructure with no UI and no app-runtime wiring (Keychain today). Bigger UI-free subsystems live in `Packages/<Name>/` instead (BuddyAccessibility, BuddyVoice).
- `Resources/` — `.xcstrings`, JSON flows, future assets. No code.
- Cross-feature dep direction: `App → Features → Core`. Never the other way; never Feature → Feature. `App/Session/` is allowed to import from any Feature — it is the wiring layer.

### Permissions plumbing

`PermissionsCoordinator.request(_:)` is the only public entry point. It deep-links to System Settings on the *second* tap (for AX / Screen) or when the OS has already denied (for Mic), prompts otherwise, and guards against double-fire while a prompt is in flight. Avoid calling the private `requestAccessibility/requestScreenCapture` helpers directly.

### Permission gating model (important)

The app is **hard-gated**: nothing useful runs until all three permissions are granted. The pattern is:

1. The Start Listening menu item is always clickable so the user gets feedback.
2. On click it calls `permissions.refresh()` then checks `allGranted`. If false → `onboarding.blockForPermissions()` + open the main window. If true → start the session (currently an `NSLog` stub).
3. `MainWindow` observes `permissions.allGranted` and auto-routes back to `.home` when the user grants the last missing permission — no "Try again" button needed.

## Localization

Single string catalog at `BuddyAka/Resources/Localizable.xcstrings`, three locales: `en` (source), `ru`, `uz`. **`uz` is Latin script, not Cyrillic** — this is the dominant script in Uzbekistan today.

Rules:
- All user-facing strings go through `String(localized: "…")` (or implicit `Text("…")` in SwiftUI, which also resolves the catalog).
- `NSMenuItem` titles need the explicit `String(localized:)` form because AppKit doesn't auto-resolve — relevant if you ever bypass the SwiftUI `MenuBarExtra`.
- Do **not** localize: the app name "BuddyAka", the bundle ID, `NSLog` messages, code comments. For brand-name `Text` use `Text(verbatim: "BuddyAka")` — plain `Text("BuddyAka")` gets auto-extracted into the catalog by Xcode.
- Narration produced by Gemini Live is **not** in the catalog — Gemini generates it in the user's language at runtime. Only UI chrome lives here.
- When adding a string: put it in the catalog with all three locales translated, in the same JSON shape as existing entries. Translations are pattern-matched, not authoritative — flag any external-demo-bound strings for native review.

## Dependencies

No third-party SwiftPM packages currently. `architecture.md` §4 has the approved list (AXSwift, KeyboardShortcuts, Defaults) — add only when the build order calls for them, and only from that list. Anything else needs justification against §4's rejected list.

**Divergence from §4: AXSwift is not used.** Last commit 2021-11-14 (dormant 4+ years). The C-API surface we need is ~8 functions and the package owns its own thin helper instead (`Packages/BuddyAccessibility/Sources/BuddyAccessibility/AXAttr.swift`). Step 6's `AXObserver → AsyncStream` bridge will live in the same package.

## Local SwiftPM packages

`Packages/BuddyAccessibility/` contains library `BuddyAccessibility` (linked into the app target) and executable `axdump` (CLI dev tool). `Packages/BuddyVoice/` contains the Gemini Live WebSocket protocol and audio capture/playback pipeline. The pattern: Core subsystems with no SwiftUI surface live in a `Packages/<Name>/` SwiftPM package and are imported by `App/` and `Features/`. Future Screenshot / Planner subsystems should follow.

Tests live inside the package and run via `swift test` from the package directory — there is no XCTest target on the main Xcode project.

### CLI: `axdump`

Dumps a target app's filtered AX tree to JSON. Used to tune the extractor and to author curated flows before the in-app AX inspector exists.

```
swift run --package-path Packages/BuddyAccessibility axdump --bundle com.apple.Safari --pretty
swift run --package-path Packages/BuddyAccessibility axdump --frontmost --pretty
swift run --package-path Packages/BuddyAccessibility axdump --pid 1234 -o /tmp/snap.json
```

**One-time setup:** the CLI inherits the running terminal's TCC identity, so your terminal (Terminal / iTerm / Ghostty / etc.) needs Accessibility granted in System Settings → Privacy & Security → Accessibility. Exit code `2` from `axdump` means this grant is missing.

### AX notification volume in Safari (observed, Step 6)

`axdump --bundle com.apple.Safari --watch N` confirms the expected shape: `focused_element_changed` / `focused_window_changed` fire on real user actions, `layout_changed` is collapsed to near-zero by the 200 ms debouncer, menu open/close work. **The session bridge no longer registers for `value_changed` or `element_destroyed`** — in Safari, `value_changed` floods (URL-field typing, scroll position, focus rings — dozens per second) and `element_destroyed` bursts (hundreds of events when swapping pages); no consumer used them. The `AXEvent.valueChanged` / `AXEvent.elementDestroyed` enum cases stay (axdump's `--watch` formatter still references them, and the bridge's `switch` retains defensive no-op cases), so the existing guidance below — don't treat them as generic advance triggers when authoring `advance_when` matchers (Step 7) — still applies to anything that reaches the stream through other paths.

`element_destroyed` also bursts (hundreds of events in <1 s when Safari swaps pages). Currently log-only; same guidance — don't drive flow advance from it generically. The genuine advance signal during a Safari nav is the `focused_element_changed` that follows the destruction burst.

Mouse clicks are intentionally monitored during a session as a fallback for native macOS apps such as System Settings, where AX focus/window notifications are often sparse. Treat clicks as user-action signals, not proof of success: click-on-halo may advance after a short settle window; click-off-halo should recapture state as `user_clicked_elsewhere`; AX destruction/value/layout bursts remain passive unless a future curated-flow matcher explicitly opts in.

## Conventions

- Swift Concurrency (`async/await`, `AsyncStream`, actors). No GCD unless an API forces it.
- macOS 14+ target. State containers use the `@Observable` macro from `Observation`, not `ObservableObject` / `@Published`.
- `@MainActor` annotate state containers that mutate UI-bound properties. The project default actor isolation is also `MainActor` (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).
- Default to no comments. Only write a comment when the WHY is non-obvious (the existing `// Prompt option triggers …` in `PermissionsCoordinator` is the right standard).
- Fail fast: APIs that can fail should `throw` (see `Core/Keychain/KeychainStore.swift`) — do not return `Bool` or swallow `OSStatus`. UI surfaces real error messages, not silent success.
- The Settings scene is for advanced tweaking. First-time onboarding and revocation recovery happen in the main `Window`, not in Settings.

## What works today vs. what's stubbed

Per `architecture.md` §11:

- **Step 1 (app shell + permissions onboarding):** done with polish.
- **Step 2 (AX extractor + normalized UI JSON serializer + CLI):** library landed in `Packages/BuddyAccessibility`. `AXExtractor.extract(target:options:)` returns a `UISnapshot` matching arch §5.6 plus a session-local `AXSnapshotResolver` for id → live `AXUIElement` lookup. `axdump` CLI works. AX output normalizes through `Packages/BuddyUIModel`.
- **Step 3 (overlay window + buddy cursor + halo):** landed in `Features/Overlay`. It creates one transparent click-through overlay per screen and starts hidden until a session begins.
- **Step 4 (Gemini Live client + audio loop):** landed in `Packages/BuddyVoice` and `App/Session/`. Start Listening enforces permissions/API key, shows the overlay, opens a Gemini Live audio session, streams mic PCM, and plays model audio.
- **Step 5 (tools end-to-end):** `get_ui_tree` and `point_to_element` are declared, dispatched by `ToolDispatcher`, and answered with the live normalized `UISnapshot` / target frame. Pointing drives the halo through `OverlayState`.
- **Step 6 (AX event stream + guidance signals):** `AXEventStream` / `AXObserverBridge` / `LayoutChangeDebouncer` landed in `Packages/BuddyAccessibility`; `MouseClickSignalSource` + `GuidanceSignalController` landed in `App/Session/`. `SessionCoordinator` enters `.guiding` on `point_to_element`, watches AX + mouse, and emits `[BUDDY_SIGNAL]` turns (`target_clicked`, `screen_changed`, `user_clicked_elsewhere`, `idle_timeout`) back to the model.

Next on the build order: step 7 (curated-flow walker — load `Resources/Flows/*.json`, match steps via `advance_when`, drive the persona through scripted flows).
