# Architecture — Voice-Guided On-Screen Onboarding Buddy

Companion to `specifications.md`. This doc covers the **technical decisions, dependencies, and module layout** needed to build the macOS app.

---

## 1. Top-Level Stack — Locked

| Concern | Decision |
|---|---|
| Platform | macOS 14+ (Sonoma) — needed for `ScreenCaptureKit` ergonomics and modern AX behavior |
| Language | Swift 5.10+ |
| UI | SwiftUI + AppKit interop (`NSHostingView` inside `NSWindow`) for the overlay |
| App shell | **Menu bar app** (`LSUIElement = true`) — no dock icon; status bar item to start/stop |
| Sandboxing | **Off.** Accessibility + Screen Recording APIs are incompatible with the App Sandbox |
| Signing (hackathon) | **Free Apple ID "Personal Team"** Apple Development cert via Xcode auto-managed signing. Produces a stable Designated Requirement, so TCC (Accessibility + Screen Recording) grants persist across rebuilds. No $99 Developer Program membership needed for local builds. Every team member signs into Xcode with the same Apple ID OR uses their own — bundle ID + Personal Team identity is what TCC keys on, so each dev grants permissions once per machine and they stick |
| Signing (post-hackathon distribution) | Paid Developer ID cert ($99/yr) for notarized `.app` distribution outside the Mac App Store. Not required to demo |
| Concurrency | Swift Concurrency (`async/await`, `AsyncStream`, actors). No GCD unless forced |
| Backend | **None.** Mac app talks directly to Gemini Live. API key prompted in-app on first launch → stored in macOS Keychain. Curated flows shipped as bundle resources |
| Build | Xcode project, SwiftPM for dependencies |

### Why no backend (for hackathon)
- Latency: every extra hop hurts. Voice flow already has Gemini round-trip; a proxy adds 50-150ms.
- Infra: zero infra means zero infra failures during demo.
- Secrets: API key in Keychain is fine for a hackathon; not shippable to end users but that's a post-hackathon problem.
- Curated flows are static JSON — they belong in the app bundle, not a server.

**If/when we productize:** thin Cloudflare Worker as Gemini proxy + key broker; curated flows still bundled (or fetched at launch and cached).

---

## 2. macOS Permissions

The app must request and verify three permissions on first launch. Permission state is checked at startup and re-checked before each session.

| Permission | API | TCC bucket |
|---|---|---|
| Accessibility | `AXIsProcessTrustedWithOptions` | `kTCCServiceAccessibility` |
| Screen Recording | `CGRequestScreenCaptureAccess` (macOS 11+) | `kTCCServiceScreenCapture` |
| Microphone | `AVCaptureDevice.requestAccess(for: .audio)` | `kTCCServiceMicrophone` |

Onboarding screen walks the user through granting each, with deep links to System Settings panes (`x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`).

---

## 3. Module Layout

```
BuddyAka/
├── App/
│   ├── BuddyAkaApp.swift              # @main, status bar item
│   ├── PermissionsCoordinator.swift   # checks & requests Accessibility/ScreenCapture/Mic
│   ├── OnboardingView.swift           # first-launch permission walkthrough
│   ├── APIKeySettingsView.swift       # prompts for Gemini API key on first launch
│   └── KeychainStore.swift            # thin Keychain wrapper (~30 lines) for API key
├── Voice/
│   ├── GeminiLiveClient.swift         # WebSocket lifecycle, audio in/out, tool dispatch
│   ├── AudioCapture.swift             # AVAudioEngine mic tap → PCM frames
│   ├── AudioPlayer.swift              # AVAudioPlayerNode for streamed TTS chunks
│   └── ToolRegistry.swift             # exposes AX/screenshot/cursor tools to Gemini
├── Accessibility/
│   ├── AXTreeExtractor.swift          # serialize focused-app AX tree → normalized UI JSON
│   ├── AXElementResolver.swift        # element_id → CGRect frame lookup
│   ├── AXObserverBridge.swift         # AXObserver registration + AsyncStream of events
│   └── AXEventDebouncer.swift         # collapses LayoutChanged storms
├── Screenshot/
│   └── WindowCapture.swift            # ScreenCaptureKit on-demand capture (fallback)
├── Inspector/
│   ├── AXInspectorWindow.swift        # dev-only debug window showing live normalized UI tree of focused app
│   ├── AXTreeOutlineView.swift        # NSOutlineView/SwiftUI hierarchy with role, label, identifier, frame
│   └── CopyAsMatcherCommand.swift     # right-click → copies a `role`+`label` (or `identifier`) matcher JSON to clipboard
                                       # Gated behind a debug build flag. Powers the flow-authoring loop (flow-schema.md §6)
├── Overlay/
│   ├── OverlayWindowController.swift  # transparent click-through NSWindow
│   ├── BuddyView.swift                # SwiftUI: animated mouse-cursor graphic
│   ├── HaloView.swift                 # SwiftUI: pulsing ring around target frame
│   └── CursorAnimator.swift           # spring-animated position binding
├── Planner/
│   ├── PlanState.swift                # task, steps[], currentIndex, status (actor)
│   ├── CuratedFlowStore.swift         # loads bundled + user-imported Flows/*.json, hot-reloads on FS changes
│   ├── FlowImporter.swift             # NSOpenPanel + drag-drop import, validates against FlowSchema
│   ├── FlowsLibraryView.swift         # SwiftUI settings list: name, bundle ID, step count, enable/delete
│   └── FlowSchema.swift               # Codable types for curated flows
├── Coordinator/
│   └── SessionCoordinator.swift       # the brain — wires voice ↔ AX ↔ overlay ↔ plan
└── Resources/
    ├── Flows/
    │   ├── soliq/
    │   │   ├── file_vat_report.json
    │   │   └── ...
    │   └── uzum/
    │       └── ...
    └── Assets.xcassets/               # buddy cursor sprite, halo gradient, app icon
```

---

## 4. Dependencies (SwiftPM)

| Package | Purpose | Why |
|---|---|---|
| [`AXSwift`](https://github.com/tmandry/AXSwift) | Idiomatic Swift wrapper over `AXUIElement` C API | The raw C API is painful from Swift. AXSwift gives us `UIElement` types, attribute access, and observer wiring with less boilerplate |
| [`KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) (sindresorhus) | Global hotkey to toggle the buddy | **⌘⇧B** toggles the buddy: press to summon (start listening + show overlay); press again to dismiss. Voice "stop / cancel" also dismisses. ⌘⇧N considered and discarded — conflicts with Finder "New Folder", Chrome incognito, Notes new note |
| [`Defaults`](https://github.com/sindresorhus/Defaults) (sindresorhus) | Type-safe `UserDefaults` | Minor convenience — for storing API key reference, last-used flow, preferences |
| Native: `URLSessionWebSocketTask` | Gemini Live WebSocket | No third-party WS client needed |
| Native: `AVFoundation` | Mic capture, audio playback | `AVAudioEngine`, `AVAudioPlayerNode` |
| Native: `ScreenCaptureKit` | Window screenshot fallback | Modern (macOS 12.3+), replaces `CGWindowListCreateImage` |
| Native: `os.Logger` | Logging | No need for swift-log |
| [`SwiftLint`](https://github.com/realm/SwiftLint) | Static analysis / style enforcement | **From day one.** Wired as a build phase + pre-commit hook. Default rules + a project `.swiftlint.yml` to disable a handful of noisy rules. Code hygiene compounds; cheaper to enforce early than fix later |

### Considered and rejected for hackathon
- **`generative-ai-swift`** (Google's official Swift SDK): now **fully deprecated** — repo renamed to `deprecated-generative-ai-swift`. Don't use.
- **Firebase AI Logic SDK** (Google's current official Swift path): *does* support Live API, but drags in the full Firebase SDK and requires a Firebase project. Too heavy for our needs.
- **`paradigms-of-intelligence/swift-gemini-api`** (community): supports Live with WebSockets. Tempting, but ~9 stars, single maintainer, first release Dec 2025 — too risky for a demo we're betting on.
- **Decision: hand-roll WebSocket** via `URLSessionWebSocketTask`. Protocol is documented; we control every layer; ~one file of work.
- **`lottie-ios`**: nice for animated character, but a static PNG + SwiftUI spring animation looks great and saves a dependency.
- **`Sparkle`**: auto-updates — irrelevant for hackathon.

---

## 5. Gemini Live Integration

### 5.1 Connection
- WebSocket endpoint: `wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent` (or the v1 equivalent at build time).
- Model: `gemini-3.1-flash-live` (per spec §3.5).
- Auth: API key as query param or header (per current SDK convention — verify at build time).
- Session config: system instruction with persona ("playful Clippy-style buddy"), tool declarations, response modality = AUDIO.

### 5.2 Audio pipeline
- **Capture:** `AVAudioEngine` input node tap → resample to 16kHz mono PCM (Gemini Live requirement) → stream chunks over WebSocket.
- **Playback:** receive audio chunks (24kHz PCM out per Live spec) → feed to `AVAudioPlayerNode` with a scheduling queue → smooth realtime playback.
- **Echo cancellation:** macOS handles this if we use the right audio session category. If not, ship with "use headphones for demo."

### 5.3 Tools exposed to Gemini (function calling)

Gemini calls these via Live's tool-call mechanism; our app executes and replies in the same stream.

| Tool name | Args | Returns | Purpose |
|---|---|---|---|
| `get_ui_tree` | `(focused_window_only: bool)` | compact normalized UI tree | Primary "what's on screen" input |
| `get_screenshot` | `()` | base64 PNG of focused window | Fallback when UI extraction is sparse |
| `point_to_element` | `(element_id: string, narration: string?)` | success/fail | Moves buddy cursor + halo, optionally narrates |
| `get_curated_flow` | `(app_bundle_id: string, task: string)` | flow JSON or null | Pulls hand-curated plan if one exists |
| `mark_step_complete` | `()` | new plan state | Advances loop |
| `mark_task_complete` | `()` | none | Ends session |
| `start_tour` | `(element_ids: string[])` | current tour step | Starts Tour Mode for screen orientation, after `get_ui_tree` |
| `stop_tour` | `()` | success | Stops an active or paused tour |
| `resume_tour` | `()` | success | Resumes a paused tour after user confirmation |

### 5.3.1 Tour Mode

Tour Mode is an intentional second interaction loop for users who ask to be shown around the current screen rather than guided through a specific goal. It remains a teaching feature: Buddy only moves the overlay cursor/halo and narrates; it never clicks or mutates the target app.

Flow:

1. User asks an orientation intent such as “walk me through this screen.”
2. Gemini calls `get_ui_tree` and chooses 5-8 useful, visible elements in scan order.
3. Gemini calls `start_tour(element_ids: [...])`.
4. The app pins the current UI snapshot resolver, points to the first element, and enters `.touring(.active)`.
5. After each model `turnComplete`, the app advances the tour on a 1.5s tick and sends a typed runtime event as app-generated text: `[BUDDY_EVENT] {"type":"tour_step", ...}`.
6. Gemini narrates each event in one short sentence. It does not call `point_to_element` while the app owns the halo.
7. `[BUDDY_EVENT] {"type":"tour_complete"}` ends the tour and returns the session to `.live`.

State ownership rules:

- `SessionCoordinator` is the single authority for Tour Mode transitions. `ToolDispatcher` only executes tool mechanics and validates UI snapshot freshness.
- `start_tour` is allowed only from `.live`; `point_to_element` is rejected during `.touring`; `resume_tour` is allowed only from `.touring(.paused)`; `stop_tour` is allowed from either tour phase.
- The dispatcher stores the PID for the snapshot that produced the current resolver. `point_to_element` and `start_tour` reject stale IDs if the focused target PID has changed since `get_ui_tree`.
- Target app changes abort the tour with `[BUDDY_EVENT] {"type":"tour_aborted","reason":"app_changed"}` and clear the pinned snapshot.

Interruption rules:

- Tour Mode enables barge-in capture while playback is queued so user speech can interrupt narration.
- On Gemini `serverContent.interrupted`, the app stops and clears queued playback immediately, pauses the tour, and waits for the user's turn.
- Gemini must answer the interruption normally and ask whether to continue; it may call `resume_tour()` only after user confirmation.

### 5.4 Persona system prompt (v1 — locked, iterable in rehearsal)

Sent once per Live session as `system_instruction`:

```
You are "Buddy," a friendly on-screen guide that helps people learn unfamiliar
software by pointing at the right thing to click. You never click for them —
you teach. Tone: warm, playful, lightly humorous, Clippy-with-better-manners.
Keep narration short (one or two sentences per step). Encourage progress
("nice — you got it"), normalize getting stuck ("happens to me too"), and
never condescend. Match the user's language: if they speak Uzbek, you speak
Uzbek; same for Russian, English, or any mix. When you call
`point_to_element`, your `narration` should describe what to click in plain
words, not UI jargon ("the big blue Submit button at the bottom" beats
"button 'btn-submit'"). When a step succeeds, briefly celebrate, then move
on. When the task is fully done, call `mark_task_complete` and offer to help
with something else.
```

Iterate during rehearsal — if a step lands wrong, tighten this prompt before reaching for per-step `narration` overrides.

### 5.5 Target browser for web-app flows

Hero demo runs Soliq.uz in **Safari (primary)** with **Chrome as fallback**:

- **Safari (primary):** page controls are extracted through Safari DOM when AX is sparse, with AX still used for browser/window geometry and events. Requires Automation permission and Safari's Develop → Developer Settings → "Allow JavaScript from Apple Events". Default browser on a fresh Mac — matches the "non-technical workforce" pitch. Rehearse and ship demo recordings on Safari.
- **Chrome (fallback):** DOM bridge not implemented yet. AX is lazily activated; launch Chrome with `--force-renderer-accessibility` (or set the runtime flag at `chrome://accessibility`) if using the AX fallback.
- **Other browsers (Firefox, Arc, Brave):** untested for hackathon; not blocking but document as "should work, may need browser-specific AX activation."
- `url_match` matchers in curated flows remain browser-agnostic — the substring match runs against the normalized UI snapshot URL when available.

### 5.6 Normalized UI tree JSON schema (sent to Gemini)

Compact, opinionated. We do NOT send raw AX or DOM trees — all extractors normalize into one source-agnostic schema, filter to actionable elements, redact sensitive values, and trim attributes Gemini doesn't need.

```json
{
  "app": "com.soliq.cabinet",
  "window_title": "Soliq Cabinet — Reports",
  "elements": [
    {
      "id": "e_42",
      "source": "dom",
      "role": "button",
      "label": "Create new report",
      "description": null,
      "value": null,
      "has_value": false,
      "enabled": true,
      "focused": false,
      "frame": {"x": 820, "y": 340, "w": 180, "h": 36}
    },
    ...
  ]
}
```

`id` is an opaque session-local handle our active resolver maps back to the live AX element or DOM selector for frame lookup. Frames are included so Gemini can disambiguate (e.g. two "Submit" buttons) without us doing extra round-trips. Roles are normalized semantic values (`button`, `link`, `text_field`, `checkbox`, `combobox`, etc.), never raw AX or DOM implementation names.

---

## 6. AX Event Handling

`AXObserver` notifications fire on the run-loop the observer is attached to. We attach to the main run-loop and re-publish as an `AsyncStream<AXEvent>` consumed by the `SessionCoordinator`.

```swift
enum AXEvent {
    case focusedElementChanged(UIElement)
    case focusedWindowChanged(UIElement)
    case layoutChanged
    case valueChanged(UIElement)
    case windowCreated(UIElement)
    case elementDestroyed
    case menuOpened, menuClosed
}
```

**Debouncing:** `kAXLayoutChangedNotification` can fire dozens of times during a single page render. Debouncer collapses bursts within a 200ms window into a single event.

**Subscription scope:** observer is attached to the *target app's pid*, not our own. When the focused app changes (user switches window), we tear down and re-create the observer on the new pid.

---

## 7. Overlay Window

```swift
let window = NSWindow(
    contentRect: NSScreen.main!.frame,
    styleMask: .borderless,
    backing: .buffered,
    defer: false
)
window.isOpaque = false
window.backgroundColor = .clear
window.level = .screenSaver
window.ignoresMouseEvents = true
window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
window.contentView = NSHostingView(rootView: OverlayRootView())
```

Multi-monitor: enumerate `NSScreen.screens`, create one overlay per screen. The buddy cursor lives on whichever screen the target app's focused window is on.

### Rendering
- `BuddyView`: SwiftUI view rendering the **standard macOS arrow pointer** as the buddy sprite. Sprite is a template-rendered asset (SF Symbol `cursorarrow.click` or a bundled PNG with `isTemplate = true`) so it accepts a tint. `.position(x:y:)` bound to a `@State` CGPoint, transitions wrapped in `withAnimation(.spring(response: 0.5, dampingFraction: 0.7))`. Tint comes from `@AppStorage("buddyColor")` — see §7.1.
- `HaloView`: `Circle().stroke(lineWidth: 4)` tinted with the same `@AppStorage("buddyColor")` at 0.6 opacity, sized to target frame, with `.scaleEffect` + `.opacity` keyframes in a repeating `withAnimation(.easeInOut(duration: 1.2).repeatForever())`.

### 7.1 Buddy color theming

- Settings window exposes a SwiftUI `ColorPicker("Buddy color", selection: $buddyColor)`.
- Persisted via `@AppStorage("buddyColor")` — a small `Codable` wrapper encodes `Color` as a hex string.
- Default: `Color.accentColor` (respects the user's system accent automatically).
- Both `BuddyView` and `HaloView` bind to the same value → cursor + halo always match.
- ~20 lines total; no extra dependencies.

---

## 8. Curated Flow JSON Schema

**Canonical schema lives in [`flow-schema.md`](./flow-schema.md)** — v0.1 locked, deliberately minimal. Highlights:

- A curated flow is a **structured hint**, not a script. Gemini Live owns all narration; we don't pre-author voice lines.
- Six top-level fields: `id`, `title`, `description`, `app`, `steps`. `description` is written for Gemini's consumption — it's how Gemini picks the right flow from a user's spoken intent across UZ/RU/EN.
- `app` targets `bundle_id` (native) **or** `url_match` (web apps, via the browser's AX `AXURL`).
- Steps carry `intent` (English authoring note, not user-facing) + `match` + optional `advance_when` (`focused_element_changes` default, `window_changes` for modal/navigation cases).
- Matcher atoms: `role`, `label`, `label_contains`, `identifier`. One combinator: `any_of` (for multilingual labels).
- Resolver prefers on-screen elements over off-screen matches — kills most ambiguity without needing `parent` / `all_of` in the schema.
- Global 25s "did you click it?" prompt is hardcoded, not per-step.
- Everything else (`all_of`, `parent`, `index`, `value`, `label_regex`, `preconditions`, `narration` overrides, completion detection, per-step timeouts) is deliberately deferred — all are purely additive, so cheap to add when a real flow demands them.

See `flow-schema.md` for full field rules and a worked Soliq example.

---

## 9. SessionCoordinator — The Brain

Single actor orchestrating the loop:

```swift
actor SessionCoordinator {
    func startSession() async {
        await live.connect()
        for await event in merged(liveEvents, axEvents) {
            switch event {
            case .userSpoke(let intent):
                await planTask(intent)
            case .geminiToolCall(let call):
                await dispatchTool(call)
            case .geminiAudio(let chunk):
                player.enqueue(chunk)
            case .axFocusedElementChanged:
                await maybeAdvanceStep()
            case .timeout:
                await promptUserForConfirmation()
            }
        }
    }
}
```

State machine: `Idle → Listening → Planning → Guiding → WaitingForClick → (next step | Done)`.

---

## 10. Risk Register (Technical)

| Risk | Likelihood | Mitigation |
|---|---|---|
| Gemini Live Swift WebSocket protocol nuances | Medium | Read official Python SDK source as reference; build a thin protocol layer with detailed logging |
| UI tree sparse on Electron / web apps | High | Browser DOM extraction where available; ScreenCaptureKit fallback path otherwise |
| Audio round-trip latency feels laggy | Medium | Stream Gemini's audio chunks to player as they arrive; start cursor move on first tool call, don't wait for full narration |
| Accessibility permission lost on rebuild (re-signing) | Low | Resolved: free Apple ID Personal Team Apple Development cert produces a stable signing identity (Apple DTS confirmed). TCC sticks across rebuilds as long as bundle ID + Team stay constant. Avoid ad-hoc (`codesign -s -`) builds |
| Soliq browser AX tree sparse | Medium | Demo on Safari with DOM extraction enabled; Chrome can use AX fallback with `--force-renderer-accessibility` — see §5.5 |
| UZ voice quality on Gemini 3.1 Flash Live below bar | Medium (untested) | Fall back to RU narration — Soliq users are bilingual UZ/RU. No code changes; Gemini auto-matches user's spoken language |
| Soliq UI changes mid-hackathon | Low | Record golden screenshots + AX dumps of demo flow; rehearse on exact build |
| AVAudioEngine echo if no headphones | Medium | Default to headphones for demo; investigate `AVAudioSession` voice-processing if time |

---

## 11. Build Order (suggested)

1. **App shell + permissions onboarding** (1 evening)
2. **AX extractor + normalized UI JSON serializer** with a CLI test harness (1 evening)
3. **Overlay window + buddy cursor + halo** with hardcoded coordinates (1 evening)
4. **Gemini Live client + audio loop**, no tools yet, just echo conversation (1 evening)
5. **Wire tools: `get_ui_tree`, `point_to_element`** end-to-end (1 evening)
6. **AXObserver + click-advance loop** (1 evening)
7. **Tour Mode + curated flow store + Soliq hero flow JSON** (1-2 evenings)
8. **Polish, narration tone, demo rehearsal** (final stretch)

---

## 12. Out of Scope (architecture-level)

- Windows / Linux / iOS.
- Sandboxed Mac App Store distribution.
- Multi-user accounts, telemetry, analytics.
- Self-hosted Gemini alternative.
- Offline mode.
- Auto-update infrastructure.
