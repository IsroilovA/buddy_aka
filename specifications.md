# Specifications — Voice-Guided On-Screen Onboarding Buddy

## 1. Product

A macOS desktop "buddy" that teaches users how to operate software by **showing them where to click, not clicking for them**. The user speaks an intent ("I want to file a VAT report"), and a friendly cursor moves to the correct button while a voice narrates the next step. The user clicks themselves. The loop continues until the task is complete.

**Positioning (hackathon pitch):** corporate onboarding & ed-tech for non-technical workforces. Hero demo target: **Soliq.uz** (Uzbek tax cabinet — universally painful, bilingual UZ/RU), running in **Safari** (locked — see architecture §5.5). Generality closer: **Uzum Sellers** dashboard.

**Why "guide, don't act":**
- Safer for corporate IT (no agent doing destructive things in your accounting portal).
- Actually teaches — users build muscle memory instead of becoming dependent.
- Sidesteps the agent-reliability problem that kills live demos.

## 2. Core Flow

```
[Voice in — Gemini Live native audio]
        ↓
[Intent extracted: "file VAT report"]
        ↓
[Grounding: curated flow JSON (Soliq) OR live reasoning (unseen app)]
        ↓
┌──→ [Capture UI tree: AX for native apps, DOM for supported browser pages (+ screenshot fallback)]
│        ↓
│    [Gemini: pick next element ID + narration text]
│        ↓
│    [Move buddy cursor to element frame]
│        ↓
│    [TTS narration streamed via Gemini Live]
│        ↓
│    [Wait for click — UI tree change OR voice "next"]
└────────┘ until Gemini emits task_complete OR user says "stop"
```

## 3. Locked-In Architectural Decisions

### 3.1 Multi-step loop with explicit termination
- Tasks are **multi-step plans**, not single clicks.
- Termination: Gemini emits a structured `task_complete: true` signal, **or** the user says "stop / done / cancel."
- A local `PlanState` object tracks `{ task, steps[], current_step_index, completed_steps[], status }`.

### 3.2 Click detection — event-driven, with fallbacks
- **Primary:** `AXObserver` subscribed to the target app's pid for:
  - `kAXFocusedUIElementChangedNotification`
  - `kAXFocusedWindowChangedNotification`
  - `kAXLayoutChangedNotification`
  - `kAXValueChangedNotification`
  - `kAXWindowCreatedNotification` / `kAXUIElementDestroyedNotification`
  - `kAXMenuOpenedNotification` / `kAXMenuClosedNotification`
  Events fire instantly via the run-loop — no polling cost. Debounce chatter on `LayoutChanged`.
- **Fallback A — flaky AX hosts:** for apps where AX events fire inconsistently (Electron, web views with weak ARIA), fall back to screenshot diff or a short poll loop.
- **Fallback B — silence:** if no event after 25s, voice prompt: *"Did you click it? Say next when you're ready."*
- **Manual override:** user can always say "next" to force advance.

### 3.3 UI tree as primary input, screenshot as fallback
- Extract a normalized UI tree. Native apps use macOS Accessibility via `AXUIElement`; supported browser pages may use DOM extraction when the browser's AX tree is sparse or poorly labeled.
- Serialize compact normalized UI elements and send them to Gemini. Gemini returns an **element ID**, not pixel coordinates.
- We already have the frame → cursor moves deterministically. **No OCR in the happy path.**
- Screenshot fallback triggers when: the UI tree is empty/sparse (Electron, custom canvas, unsupported browser pages), or Gemini returns `element_not_found`.

### 3.4 Grounding — hybrid hand-curated + reasoning
- **Hero demo (Soliq.uz):** hand-curated flow JSONs covering the top 3-5 tasks. Bulletproof. These define the plan upfront; the loop just executes it against the live normalized UI tree.
- **Generality demo (unseen app):** pure Gemini reasoning over the live UI tree — no pre-indexed docs, no RAG. Slower and flakier but proves the "works anywhere" thesis.
- **Skipped for hackathon:** RAG over scraped help docs. Too much infra for the timebox.

### 3.5 Voice — Gemini 3.1 Flash Live native audio
- Released 2026-03-26. Google's flagship realtime audio-to-audio model.
- Single bidirectional WebSocket stream handles STT + reasoning + TTS.
- No Whisper, no ElevenLabs, no chained STT→LLM→TTS latency.
- 90+ languages including **Uzbek** — critical for the Soliq.uz hero demo. If UZ audio quality disappoints in rehearsal, fall back to **RU narration** (Soliq users are bilingual UZ/RU — same hero demo, no rebuild needed).
- Built-in tool/function calling in the same Live stream → we expose UI-tree lookup and element-frame resolution as tools, keeping the whole loop on one connection.
- Improved acoustic nuance (pitch, pace, emphasis) vs. 2.5 Native Audio — the demo will sound noticeably more natural.
- Conversation context maintained natively by the Live session.
- For non-Live reasoning (e.g. offline plan generation from curated docs), use **Gemini 3.1 Pro Preview** (Gemini 3 Pro Preview was deprecated 2026-03-09).

### 3.6 Failure recovery — graceful degrade
1. First failure: re-capture UI tree + screenshot, re-ask Gemini once.
2. Second failure: voice ask the user — *"I can't find the Submit button — do you see it on the screen?"*
3. If user says no: suggest scrolling or check whether they're on the right page.

### 3.7 Session state
- Gemini Live session holds conversational context natively.
- Local `PlanState` mirrors the structured plan so we can resume, skip, or rewind steps without re-prompting Gemini.

## 4. Components

| Component | Responsibility | Tech |
|---|---|---|
| Voice I/O | Capture mic, play TTS | Gemini 3.1 Flash Live (native audio) |
| Intent & planning | Turn voice → structured plan | Gemini 2.0 (function calling) |
| UI extractor | Dump normalized UI tree as structured text | Swift / `AXUIElement` for native apps; DOM for supported browser pages |
| Screenshot capture | Fallback visual input | `CGWindowListCreateImage` |
| Element resolver | Map Gemini's element_id → on-screen frame | Local lookup against the active UI snapshot resolver |
| Buddy cursor | Animated overlay cursor that moves to target frame | Transparent always-on-top window |
| Click detector | Advance loop on AX events from target app | `AXObserver` event stream (see architecture §6) |
| Plan state | Track current step, completed steps, status | Local in-memory object |

## 5. Hero Demo Script (Soliq.uz)

1. User logs into Soliq.uz cabinet, opens the app.
2. User: *"Men QQS hisobotini topshirmoqchiman"* ("I want to file a VAT report").
3. Buddy: *"Got it — let's file your VAT report. First, click 'Reports' in the top menu."* Cursor glides to "Reports."
4. User clicks. UI tree changes. Loop advances.
5. Buddy: *"Now click 'Create new report' on the right."* Cursor moves.
6. … 5–8 more steps …
7. Buddy: *"All set — you've filed your VAT report. Want me to walk you through anything else?"*

## 6. Out of Scope (Hackathon)

- Agent mode (no autonomous clicking).
- Windows / Linux / mobile.
- Autonomous web automation. Browser DOM may be used only to observe and point; Buddy still never clicks, types, or mutates the page for the user.
- RAG over external help docs.
- Multi-user accounts / org management.
- Auth, billing, telemetry beyond what's needed for the demo.

## 7. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Latency feels sluggish (>3s per step) | UI tree (text) not pixels; stream Gemini response; start cursor move before TTS finishes |
| Gemini picks wrong element on first try | Graceful re-ask loop; hand-curated flows for hero demo |
| Soliq UI updates between hackathon prep and demo | Record screen+AX snapshot of demo env; rehearse on the exact build |
| UI tree empty on a web view | DOM when available; screenshot + vision fallback otherwise |
| Live demo network flakiness | Pre-recorded backup video; local cache of Soliq curated flow |

## 8. Buddy Visual — Locked

- **Moving cursor:** a mouse-pointer graphic that glides to the target. Reinforces the "this is what *you* should do with your mouse" mental model — guidance, not action.
- **Pulsing halo:** a soft animated ring drawn around the target element's frame once the buddy cursor arrives. Removes any ambiguity about which control to click.
- Both render in the same transparent, click-through `NSWindow` overlay (level `.screenSaver`, `ignoresMouseEvents = true`).
- The real system cursor is never moved or hijacked — the user stays in full control.

## 9. Narration Tone — Locked

- **Playful, Clippy-style** personality. Friendly, encouraging, mild humor. Memorable for judges and lower-stakes for end users (corporate onboarding can feel intimidating; a warm buddy de-escalates).
- System prompt to Gemini Live will set the persona explicitly so it carries through voice tone, not just word choice.

## 10. Stretch Goals (if time permits)

- **Voice commands:** "pause", "repeat that", "go back", "skip this step", "slower".
- **Multi-language narration toggle** (UZ ↔ RU ↔ EN mid-session).
- **Recording / replay mode** — capture a successful walkthrough as a reusable curated flow JSON.
- **Confidence indicator** — buddy says "I'm not 100% sure, but try clicking here" when Gemini's confidence on the element pick is low.
