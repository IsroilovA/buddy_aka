# BuddyAka

A macOS AI voice assistant that **sees your screen and guides you in real time** — showing you where to click, not clicking for you.

## The Problem

People struggle with software — whether learning new tools or completing unfamiliar tasks. Non-technical users face complex apps (government portals, Photoshop, video editors, device settings) with no real-time help. Static docs and tutorials don't connect to what's actually on screen.

**Target users:** Anyone who needs hands-on help with software — learners picking up new tools (Photoshop, Excel, video editors), non-technical users navigating unfamiliar tasks (filing taxes online, configuring system settings), employees onboarding to workplace apps.

## The Solution

BuddyAka is a macOS AI voice assistant that reads the live UI of any app — native macOS apps (System Settings, Finder, Microsoft Office, Photoshop, Final Cut Pro) and web apps in Safari (government portals, Google Workspace, Figma, Canva) — using Accessibility APIs. A buddy cursor points to the right element while Gemini Live narrates what to do. The user clicks themselves. Two modes:

- **Free-form** — ask anything about whatever's on screen; Buddy reasons over the live UI
- **Structured lessons** — importable lesson packs with step-by-step guidance for specific apps and tasks

## EdTech Impact

Turns every app on your Mac into a hands-on learning environment. Users build real muscle memory by doing, not watching. Lesson authors (teachers, IT trainers, companies) can create lesson packs for any application without writing code. Trilingual UZ/RU/EN voice support brings software education to underserved language markets.

## How It Works

1. User speaks an intent (e.g., "I want to file a VAT report")
2. BuddyAka extracts the live UI tree from the target application
3. Gemini Live identifies the correct element and calls `point_to_element`
4. A buddy cursor and pulsing halo animate to the target element
5. The user clicks it themselves — building muscle memory
6. BuddyAka detects the click, confirms progress, and the loop repeats

## Features

- **Menu-bar agent** — no dock icon, always accessible via the system tray (LSUIElement)
- **Real-time voice guidance** — bidirectional audio over a single WebSocket stream (STT + reasoning + TTS simultaneously)
- **Accessibility tree extraction** — normalized UI snapshots from native AX APIs and Safari DOM
- **Visual overlay** — transparent click-through overlay with animated buddy cursor and pulsing halo
- **Tool-use architecture** — 10 function-calling tools exposed to Gemini for UI interaction
- **Guidance signals** — click detection, AX event correlation, idle timeouts, scroll tracking
- **Tour Mode** — automated walkthrough of 5-8 screen elements with narrated sequencing
- **Lessons** — structured (YAML) and ad-hoc lessons covering 15+ apps (macOS, Google Docs, Figma, Slack, etc.)
- **Curated flows** — JSON-based scripted walkthroughs with multilingual step matchers
- **Trilingual UI** — English, Russian, and Uzbek (Latin script) via a single `.xcstrings` catalog
- **Global hotkey** — `Cmd+Shift+B` to summon BuddyAka from anywhere

## AI Model & Voice

BuddyAka uses **Gemini 3.1 Flash Live Preview** (`gemini-3.1-flash-live-preview`) — Google's native audio model that handles speech-to-text, reasoning, and text-to-speech in a single bidirectional WebSocket stream.

### WebSocket Connection

The app connects to Gemini Live via a persistent WebSocket:

```
wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent
```

- **Authentication:** API key passed as a query parameter
- **Response modality:** `AUDIO` — Gemini responds with synthesized speech
- **Activity handling:** `START_OF_ACTIVITY_INTERRUPTS` — users can barge in mid-narration
- **Session resumption:** Supports session handles for recovery across disconnects

### Audio Pipeline

| Direction | Sample Rate | Channels | Encoding | Implementation |
|-----------|------------|----------|----------|----------------|
| Capture (mic → Gemini) | 16 kHz | Mono | PCM Int16 LE | AVCaptureSession |
| Playback (Gemini → speaker) | 24 kHz | Mono | PCM Int16 | AVAudioEngine + AVAudioPlayerNode |

A half-duplex gate drops mic frames while playback is active, preventing Gemini from hearing its own voice.

### Persona System

The system prompt is dynamically composed from ~19 sections covering identity, tone, cultural awareness (UZ/RU bilingual sensitivity), frustration handling, error recovery, privacy, and per-language grammar norms. Gemini adapts narration detail based on the user's perceived skill level.

### Tools Exposed to Gemini

BuddyAka declares 10 function-calling tools in the Gemini Live session:

| Tool | Purpose |
|------|---------|
| `get_ui_tree` | Returns the normalized UI tree (supports `focused_window_only`) |
| `point_to_element` | Moves buddy cursor + halo to an element by ID |
| `start_tour` | Begins Tour Mode with 5-8 element IDs in scan order |
| `stop_tour` | Ends the current tour |
| `resume_tour` | Resumes a paused tour after user interruption |
| `start_lesson` | Begins a lesson by `lesson_id` (curated) or `topic` (ad-hoc) |
| `advance_lesson_step` | Moves to a specific step or finishes the lesson |
| `list_lessons` | Returns the catalog of available lessons |
| `exit_lesson` | Drops out of the current lesson, keeping the session alive |
| `stop_pointing` | Hides the halo without ending the session |

## Requirements

- **macOS 14+** (Sonoma or later)
- **Xcode 16+** (uses `PBXFileSystemSynchronizedRootGroup` synchronized folders)
- **Apple ID** (free Personal Team signing — no paid Developer Program needed)
- **Gemini API key** ([Get one from Google AI Studio](https://aistudio.google.com/apikey))

## Setup & Installation

### 1. Clone and build

```bash
git clone <repo-url>
cd BuddyAka
xcodebuild -project BuddyAka.xcodeproj -scheme BuddyAka -destination "platform=macOS" build
```

Or open `BuddyAka.xcodeproj` in Xcode and press `Cmd+R`.

### 2. First launch

The app is a **menu-bar agent** — it opens no window by default. Look for the sparkle icon in the right side of the menu bar. The main window opens automatically on first launch for the onboarding wizard.

### 3. Grant permissions

BuddyAka requires three macOS permissions to function. The onboarding wizard guides you through each one:

| Permission | Why | Where to grant |
|------------|-----|---------------|
| **Accessibility** | Read the UI tree of any app + subscribe to AX events | System Settings → Privacy & Security → Accessibility → enable BuddyAka |
| **Screen Recording** | Screenshot fallback for visual context | System Settings → Privacy & Security → Screen Recording → enable BuddyAka |
| **Microphone** | Capture voice input for Gemini Live | Granted via the system prompt on first use |

The app is **hard-gated**: nothing useful runs until all three are granted. The permission status auto-refreshes when you return to the app from System Settings.

### 4. Configure Safari (for web app guidance)

To enable BuddyAka's DOM extraction from Safari:

1. Open **Safari → Settings → Advanced**
2. Check **"Show features for web developers"**
3. Go to the new **Developer** menu → **Developer Settings**
4. Enable **"Allow JavaScript from Apple Events"**

This allows BuddyAka to extract the DOM tree from Safari pages (the primary browser for the Soliq.uz hero demo).

### 5. Enter your Gemini API key

The onboarding wizard prompts for your API key, which is stored securely in the **macOS Keychain**. You can also set it later via the app's Settings (`Cmd+,`) → API Key tab.

### 6. Testing locales

Launch with a specific locale:

```bash
# Russian
open BuddyAka.app --args -AppleLanguages '(ru)'

# Uzbek (Latin script)
open BuddyAka.app --args -AppleLanguages '(uz)'
```

### 7. Reset onboarding

```bash
defaults delete dev.alisher.BuddyAka
```

## Architecture

### App Structure

BuddyAka is a single SwiftUI `App` with three scenes:

- **Main Window** (`Window("BuddyAka", id: "main")`) — the only user-facing window. Routes between `.wizard`, `.home`, and `.blocked` based on `OnboardingState.route`.
- **Menu Bar Extra** (`MenuBarExtra`) — always present; icon shows a warning dot when permissions are missing.
- **Settings** (`Settings`) — `Cmd+,` with tabs for Permissions, API Key, Buddy preferences, and Lessons.

A minimal `AppDelegate` exists solely for `applicationShouldHandleReopen` (re-opens the main window when clicking the .app in Finder while already running).

### State Containers

Both are `@MainActor @Observable` (macOS 14+ pattern — no `ObservableObject` / `@Published` / `@StateObject` anywhere). Owned by `BuddyAkaApp` as `@State` and injected via `.environment()`:

- **`PermissionsCoordinator`** — single source of truth for TCC permissions. Exposes `allGranted`, `missing`, and auto-refreshes on `NSApplication.didBecomeActiveNotification`.
- **`OnboardingState`** — manages `route`, `currentStep`, and `hasCompletedOnboarding` (persisted via `UserDefaults`).

### Session Coordinator

`SessionCoordinator` is the orchestrator that wires everything together during an active guidance session:

```
SessionState: idle → connecting → live → guiding → settling → ...
                                      → touring(.active / .paused)
                                      → lesson
```

It consumes events from:
- `GeminiLiveClient` (WebSocket messages, tool calls, audio)
- `AXEventStream` (accessibility notifications from the target app)
- `MouseClickSignalSource` (global click monitoring)
- `ScrollSignalSource` (scroll detection)
- Workspace notifications (app switches)

### Guidance Signal Loop

When Gemini calls `point_to_element`, BuddyAka enters `.guiding` state and emits `[BUDDY_SIGNAL]` turns back to the model:

| Signal | Meaning |
|--------|---------|
| `targetClicked` | User clicked within 40px of the target element |
| `screenChanged` | AX event indicates UI progress (focus/layout/window change) |
| `userClickedElsewhere` | Click outside target + no AX progress detected |
| `userClickedElsewhereScreenChanged` | Click outside target but AX shows progress |
| `idleTimeout` | No interaction for 40s (max 2 prompts, 25s apart) |
| `targetScrolledOffScreen` | Target element scrolled out of view |
| `targetValueChanged` | Watched element's value changed (e.g., form field input) |

Click detection uses a 400ms settle debounce correlated with AX events to confirm user progress.

### Overlay System

The visual overlay is a transparent, click-through `NSWindow` at `.screenSaver` level:

- **Buddy Cursor** — SF Symbol arrow (`cursorarrow`, 30pt) with user-selectable color, white halos, and a "BuddyAka" badge. Animates with spring physics (response: 0.5, damping: 0.7).
- **Halo** — pulsing circle stroke (4pt width, opacity 0.85→0.35) that scales between 0.92x and 1.12x over 1.2s, looping forever around the target element.
- **Multi-screen** — one overlay per `NSScreen` with coordinate conversion between AX and Cocoa systems.

### Normalized UI Tree

All UI extraction produces a unified `UISnapshot` schema:

```json
{
  "app": "com.apple.Safari",
  "window_title": "Soliq Cabinet",
  "url": "https://soliq.uz/cabinet",
  "elements": [
    {
      "id": "e_42",
      "source": "dom|ax",
      "role": "button",
      "label": "Create new report",
      "enabled": true,
      "focused": false,
      "frame": {"x": 820, "y": 340, "w": 180, "h": 36}
    }
  ],
  "stats": { "scanned": 150, "kept": 45, "truncated": false }
}
```

Element IDs are opaque and session-local — they map to live `AXUIElement` handles for frame resolution and interaction.

## Folder Structure

```
BuddyAka/
├── BuddyAka/
│   ├── App/                              # App entry, scenes, menu bar, runtime orchestration
│   │   ├── BuddyAkaApp.swift             # SwiftUI App with 3 scenes
│   │   ├── AppDelegate.swift             # applicationShouldHandleReopen only
│   │   ├── MainWindow.swift              # Route switcher (wizard / home / blocked)
│   │   ├── Menu/                         # BuddyMenu, MenuBarLabel
│   │   └── Session/                      # Cross-cutting session orchestration
│   │       ├── SessionCoordinator.swift   # Main orchestrator (state machine + event merging)
│   │       ├── ToolDispatcher.swift        # Tool execution engine
│   │       ├── ToolSchema.swift            # 10 tool declarations for Gemini
│   │       ├── GuidanceSignalController.swift  # Click detection + AX correlation
│   │       ├── MouseClickSignalSource.swift    # Global click monitoring
│   │       └── TargetApplicationTracker.swift  # Tracks which app is being guided
│   │
│   ├── Features/                         # One folder per user-visible surface
│   │   ├── Onboarding/                   # OnboardingState, WizardView, steps
│   │   ├── Home/                         # HomeView (post-onboarding landing)
│   │   ├── Permissions/                  # PermissionsCoordinator, PermissionKind, UI
│   │   ├── APIKey/                       # APIKeyField, APIKeySettingsView
│   │   ├── Overlay/                      # OverlayState, OverlayController, halo/cursor views
│   │   └── BuddySettings/               # Settings panel (color, voice, language)
│   │
│   ├── Core/                             # Cross-cutting infra, no UI
│   │   └── Keychain/                     # KeychainStore (throws), KeychainError
│   │
│   └── Resources/                        # Assets, localization, data
│       ├── Localizable.xcstrings         # String catalog (en, ru, uz)
│       ├── Flows/                        # Curated flow JSON files
│       └── Lessons/                      # Lesson YAML files (15+ apps)
│
├── Packages/
│   ├── BuddyAccessibility/              # AX extraction, event stream, observer bridge
│   │   └── Sources/BuddyAccessibility/
│   │       ├── AXExtractor.swift          # UI tree extraction (AX + DOM)
│   │       ├── AXEventStream.swift        # AsyncStream<AXEvent> from AX notifications
│   │       ├── AXObserverBridge.swift      # CFRunLoop → Swift Concurrency bridge
│   │       ├── LayoutChangeDebouncer.swift # 200ms burst collapse for layout events
│   │       └── AXAttr.swift               # Thin C-API helper (replaces AXSwift)
│   │
│   ├── BuddyVoice/                       # Gemini Live WebSocket + audio pipeline
│   │   └── Sources/BuddyVoice/
│   │       ├── GeminiLiveClient.swift      # WebSocket connection management
│   │       ├── GeminiLiveProtocol.swift    # Wire protocol (setup, audio, tool calls)
│   │       ├── AudioFormats.swift          # PCM format definitions (16kHz/24kHz)
│   │       ├── PersonaPrompt.swift         # Dynamic system prompt composition
│   │       └── BuddyLanguage.swift         # Language support (uz, ru, en)
│   │
│   └── BuddyUIModel/                     # Normalized UI snapshot schema
│       └── Sources/BuddyUIModel/
│           └── UISnapshot.swift            # UISnapshot, UIElement, UIStats
│
├── architecture.md                        # Technical architecture spec
├── specifications.md                      # Product spec
└── flow-schema.md                         # Curated flow JSON schema
```

### Dependency Direction

```
App/ → Features/ → Core/
 ↓
Packages/ (BuddyAccessibility, BuddyVoice, BuddyUIModel)
```

Feature folders never import each other. `App/Session/` is the wiring layer — it may import from any Feature or Package.

## Local SwiftPM Packages

| Package | Purpose |
|---------|---------|
| `BuddyAccessibility` | AX tree extraction, event stream (`AsyncStream<AXEvent>`), observer bridge, layout debouncer. Also contains the `axdump` CLI tool. |
| `BuddyVoice` | Gemini Live WebSocket client, audio capture/playback pipeline, persona prompt system, language support. |
| `BuddyUIModel` | Normalized `UISnapshot` schema shared across extraction sources (AX, DOM, screenshot). |

### `axdump` CLI

A dev tool that dumps a target app's filtered AX tree to JSON. Useful for tuning extraction and authoring curated flows:

```bash
# Dump Safari's AX tree
swift run --package-path Packages/BuddyAccessibility axdump --bundle com.apple.Safari --pretty

# Dump the frontmost app
swift run --package-path Packages/BuddyAccessibility axdump --frontmost --pretty

# Dump by PID to a file
swift run --package-path Packages/BuddyAccessibility axdump --pid 1234 -o /tmp/snap.json

# Watch live AX events
swift run --package-path Packages/BuddyAccessibility axdump --bundle com.apple.Safari --watch 60
```

Your terminal app (Terminal / iTerm / Ghostty) needs Accessibility permission in System Settings for `axdump` to work. Exit code `2` means this grant is missing.

## Lessons

BuddyAka ships with a curated lesson catalog covering 15+ apps:

- **macOS** — Wi-Fi, Bluetooth, file management
- **Productivity** — Google Docs, Sheets, Slides
- **Design** — Figma, Canva, Photopea
- **AI tools** — ChatGPT, Claude, YouTube
- **Collaboration** — Slack, Jira

Lessons are defined as Markdown files with YAML frontmatter in `Resources/Lessons/`. Users can also start **ad-hoc lessons** by describing a topic — Gemini improvises the guidance without a script.

## Curated Flows

JSON-based scripted walkthroughs in `Resources/Flows/` define step-by-step guidance with multilingual element matchers:

```json
{
  "id": "soliq.file_vat_report",
  "title": "File VAT report on Soliq",
  "app": { "url_match": "soliq.uz" },
  "steps": [
    {
      "intent": "open the Reports menu",
      "match": {
        "role": "button",
        "any_of": [
          { "label": "Reports" },
          { "label": "Hisobotlar" },
          { "label": "Отчёты" }
        ]
      },
      "advance_when": "focused_element_changes"
    }
  ]
}
```

Matchers support `role`, `label`, `label_contains`, `identifier`, and `any_of` (for multilingual labels).

## Tour Mode

When a user asks for orientation (e.g., "walk me through this screen"), Gemini selects 5-8 key elements and calls `start_tour`. The app:

1. Pins the current UI snapshot
2. Points the halo at the first element
3. Advances on 2.5s ticks after Gemini finishes narrating each element
4. Emits `[BUDDY_EVENT]` turns so Gemini narrates one sentence per step
5. Handles interruptions — pauses if the user speaks, resumes on `resume_tour`

## Conventions

- **Swift Concurrency** — `async/await`, `AsyncStream`, actors. No GCD unless an API forces it.
- **`@Observable`** — macOS 14+ Observation framework. No `ObservableObject` / `@Published` anywhere.
- **`@MainActor`** — all state containers that mutate UI-bound properties. Project default actor isolation is `MainActor`.
- **Fail fast** — APIs that can fail `throw`. No `Bool` returns or swallowed `OSStatus`.
- **No sandbox** — Accessibility + Screen Recording APIs are incompatible with App Sandbox.
- **No backend** — direct Gemini API calls. API key stored in macOS Keychain.
- **Signing** — free Apple ID Personal Team with stable Designated Requirement (TCC grants persist across rebuilds).

## Build Status

Per the architecture build order:

- [x] **Step 1** — App shell + permissions onboarding
- [x] **Step 2** — AX extractor + normalized UI JSON + `axdump` CLI
- [x] **Step 3** — Overlay window + buddy cursor + halo
- [x] **Step 4** — Gemini Live client + audio loop
- [x] **Step 5** — Tools end-to-end (`get_ui_tree`, `point_to_element`)
- [x] **Step 6** — AX event stream + guidance signals
- [ ] **Step 7** — Curated-flow walker (load `Flows/*.json`, match steps, drive persona)

## License

All rights reserved.
