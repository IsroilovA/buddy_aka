# Curated Flow JSON Schema — v0.1

A curated flow is a **structured hint** that tells the buddy *what task this is* and *which elements to point at*. Gemini Live owns the narration — it speaks naturally about each step in the user's language. We don't pre-author voice lines.

Files live in:
- `BuddyAka.app/Contents/Resources/Flows/` (shipped with the app)
- `~/Library/Application Support/BuddyAka/Flows/` (user-imported via UI)

`CuratedFlowStore` loads both, hot-reloads on filesystem changes, and validates via `Codable` decode at import time. Malformed files are rejected with a surfaced error.

---

## 1. Top-Level Shape

```json
{
  "id": "soliq.file_vat_report",
  "title": "File VAT report on Soliq",
  "description": "Walks the user through filing a quarterly VAT report on soliq.uz",
  "app": { "url_match": "soliq.uz" },
  "steps": [ /* see §3 */ ]
}
```

### Field rules

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | string | yes | Unique, dot-namespaced (`<app>.<task>`). Used for filenames and logs |
| `title` | string | yes | Short English label shown in the Settings flow library. Gemini translates live if the user's language differs |
| `description` | string | yes | One-sentence English summary of what the flow does. **Used by Gemini to match the user's spoken intent to the right flow** — write it like a job description |
| `app` | object | yes | Targeting — must have `bundle_id` **or** `url_match` |
| `steps` | array | yes | Ordered. Must have ≥1 |

### `app` block

```json
{ "bundle_id": "com.apple.mail" }
// OR
{ "url_match": "soliq.uz" }
```

| Field | Notes |
|---|---|
| `bundle_id` | Matches `NSRunningApplication.bundleIdentifier` — for native macOS apps |
| `url_match` | Substring match against the frontmost browser tab URL — for web apps. Read from the normalized UI snapshot URL when available |

Exactly one of the two must be present.

---

## 2. Why no narration field

Gemini Live is an audio-native model with a persona system prompt. Given the normalized UI tree and the step's `intent`, it generates spoken narration directly — in the user's language, with natural pacing, adapted to the actual screen state. Pre-authoring narration text would mean asking Gemini to read our lines instead of letting it talk, which:

- doubles the multi-language authoring work,
- makes flows feel scripted,
- wastes the model's native capability.

Tone consistency (playful Clippy persona) comes from the Live session's **system prompt**, not from per-step strings.

**Escape hatch:** if a specific step misbehaves in rehearsal (Gemini says something off-tone or wrong), we can add an optional `narration` override field on just that step. We have NOT added it yet — wait until a real demo problem demands it.

---

## 3. Step Shape

```json
{
  "intent": "open the Reports menu at the top",
  "match": { /* element matcher — see §4 */ },
  "advance_when": "focused_element_changes"
}
```

| Field | Type | Required | Default |
|---|---|---|---|
| `intent` | string | yes | English authoring note. **Not user-facing.** Gemini reads this as context to generate spoken narration. Write it in the imperative ("click X", "open Y") |
| `match` | matcher object | yes | How to find the target element on screen — see §4 |
| `advance_when` | enum | no | `focused_element_changes` |

### `advance_when` values

| Value | Meaning |
|---|---|
| `focused_element_changes` *(default)* | AX focus moved — typical for button clicks, link clicks, text field clicks |
| `window_changes` | Front window or window title changed — use after steps that open a modal, sheet, or navigate to a new page where AX focus may not shift |

Anything fancier (`value_equals`, `element_appears`, `manual_only`) is **deferred**. Add when a real flow needs it.

The session also has a **global 25s "no-progress" prompt**: if neither event fires within 25s of the buddy pointing at the target, the buddy asks *"Did you click it? Say next when you're ready."* This is hardcoded, not per-step.

---

## 4. Element Matcher Grammar

Matchers run against the live normalized UI tree at execution time, not at authoring time. Cosmetic UI tweaks on the target app don't break flows.

### Atoms

| Key | Type | Meaning |
|---|---|---|
| `role` | string | Normalized role — e.g. `button`, `text_field`, `text`, `link` |
| `label` | string | Exact match against AX label (case-insensitive) |
| `label_contains` | string | Substring match against AX label (case-insensitive) |
| `identifier` | string | Exact match against `AXIdentifier`. **Most stable when the app sets it** — prefer this above all else |

### Combinator

| Key | Notes |
|---|---|
| `any_of` | Array of matcher objects, OR semantics. **Use for multilingual labels.** This is the only combinator in v0.1 |

### Resolver behavior

When a matcher resolves to multiple elements, the resolver picks the **on-screen** element (i.e. inside the focused window's visible frame) over off-screen matches. This eliminates most ambiguity without needing `parent` / `all_of` / `index` in the schema.

### Author guidance (in order of preference)

1. **`identifier`** if the app exposes one. Survives label changes and localization.
2. **`role` + `label`** for stable native UIs.
3. **`role` + `any_of: [{label: ...}]`** for multilingual UIs — the Soliq case.
4. **`role` + `label_contains`** when labels shift with state (`"Save"` → `"Saving…"`).

### Deferred (add when needed)

`all_of`, `parent`, `not`, `index`, `label_regex`, `value`. All purely additive — adding any of them later requires no migration of existing flows. Don't add them speculatively.

---

## 5. Full Example — Soliq.uz "File VAT Report"

```json
{
  "id": "soliq.file_vat_report",
  "title": "File VAT report on Soliq",
  "description": "Guides the user through filing a quarterly VAT report in the Soliq cabinet on soliq.uz. Use when the user wants to submit, file, or send a VAT/QQS/НДС report.",
  "app": { "url_match": "soliq.uz" },
  "steps": [
    {
      "intent": "open the Reports menu at the top of the cabinet",
      "match": {
        "role": "button",
        "any_of": [
          { "label": "Reports" },
          { "label": "Hisobotlar" },
          { "label": "Отчёты" }
        ]
      }
    },
    {
      "intent": "click Create new report on the right side",
      "match": {
        "role": "button",
        "label_contains": "Create"
      },
      "advance_when": "window_changes"
    },
    {
      "intent": "choose VAT from the report type list",
      "match": {
        "role": "button",
        "any_of": [
          { "label_contains": "VAT" },
          { "label_contains": "QQS" },
          { "label_contains": "НДС" }
        ]
      }
    }
  ]
}
```

Note how `description` is written for **Gemini's consumption** — it lists the target task in multiple phrasings/languages so Gemini reliably picks this flow when the user says "I want to file my VAT report" or "QQS hisobotini topshirish."

---

## 6. Authoring Workflow

1. Open the target app in the state you'd start from (e.g. logged into Soliq cabinet).
2. Walk through the task manually with the buddy's debug UI inspector open (a side panel showing the live normalized UI tree).
3. Right-click any element in the inspector → "Copy as matcher" — pastes a `role` + `label` matcher to clipboard.
4. Paste into a step, add a short imperative `intent`, save.
5. Drag the JSON onto the Settings window → `CuratedFlowStore` hot-reloads.
6. Try the flow with voice ("hey buddy, file a VAT report"). Iterate.

The AX inspector + "Copy as matcher" tool is small (~half a day) and pays back massively the first time you author a flow.

---

## 7. What's Deliberately Not in v0.1

| Deferred feature | Add when |
|---|---|
| `narration` override on a step | A rehearsal shows Gemini saying something wrong/off-tone on a specific step |
| `all_of` / `parent` combinators | A flow has two matching elements and visibility ranking can't disambiguate |
| `index` matcher | Same as above, after `all_of`/`parent` |
| `value`, `label_regex` | A flow needs form-field inspection or pattern matching |
| `preconditions` | A flow keeps starting in the wrong app state and Gemini can't recover gracefully |
| `completion.detect` | We start mis-firing "task complete!" on failed submits |
| Per-step `timeout_seconds` / `on_timeout` | Global 25s prompt stops being sufficient |
| Localized `title` / `description` | The flow library UI needs to display in UZ/RU before Gemini's live translation |

Every item above is **purely additive** — adding it later doesn't break existing flows. That's the design test for what stays out: if it's deferrable AND cheap to add, it stays out.
