---
id: google_docs.write_and_format
title: Write and format a document
language_hints:
  uz: Hujjat yozing va formatlang
  ru: Напишите и отформатируйте документ
app:
  url_match: docs.google.com/document
prerequisites:
  - You have an internet connection and a Google account
estimated_minutes: 5
sort_order: 16
suggested_next:
  - google_docs.share_and_comment
  - sheets.first_sum_formula
---

# Write and format a document

By the end of this lesson the learner has created a Google Doc, typed a paragraph, bolded text, applied a heading style, and inserted a link. These are the four formatting moves that cover 90% of everyday document work.

**Teaching stance:** Writing and formatting are separate skills. Let the learner type anything — even "test test test" — the point is learning the tools, not writing a masterpiece. Be encouraging about their speed.

## Step 1 — Open Safari

> Click the Safari icon in your Dock — the blue compass.

```yaml
expect:
  match:
    scope: dock
    label_contains: Safari
  advance_when: focused_element_changes
  also_advance_when: window_changes
```

## Step 2 — Create a new document

> Click the address bar and type "docs.new" then press Return. A blank document opens instantly.

**Teach:** "docs.new" is a Google shortcut — no need to visit Google Drive first. The document saves itself automatically as you type.

```yaml
expect:
  match:
    scope: app_window
    role: text_field
    any_of:
      - { identifier: "WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD" }
      - { label_contains: "Address" }
  advance_when: url_contains
  advance_value: docs.google.com/document
```

## Step 3 — Type a paragraph

> Click anywhere in the blank page and start typing. Write a few sentences — anything at all. It could be about your day, a recipe, a to-do list.

**Teach:** Google Docs saves every keystroke to the cloud. You'll never lose your work, even if you close the browser by accident.

```yaml
expect:
  advance_when: focused_element_changes
```

## Step 4 — Select text and make it bold

> Use your mouse to highlight a word or phrase in your paragraph — click and drag over it. Then press Cmd+B to make it bold. You'll see the text get thicker.

**Teach:** Cmd+B is the universal bold shortcut — it works in Docs, email, Slack, nearly everywhere. Cmd+I does italic and Cmd+U does underline.

```yaml
expect:
  match:
    role: button
    any_of:
      - { label: Bold }
      - { label_contains: "Bold" }
      - { label: "Жирный" }
      - { label: "Qalin" }
  advance_when: focused_element_changes
```

## Step 5 — Apply a heading style

> Click at the very beginning of your paragraph — put the cursor before the first word. Now look at the toolbar and find the dropdown that says "Normal text". Click it and choose "Heading 1".

**Teach:** Headings structure your document into sections, like chapters in a book. "Heading 1" is the biggest — use it for main titles. "Heading 2" is for subtitles. Normal text is for everything else.

```yaml
expect:
  match:
    any_of:
      - { role: combobox, label_contains: "Normal" }
      - { role: button, label_contains: "Normal text" }
      - { role: combobox, label_contains: "Styles" }
  advance_when: focused_element_changes
  also_advance_when: window_changes
```

## Step 6 — Insert a link

> Type a new sentence below your heading. Select a word in it, then press Cmd+K. A small dialog appears — type or paste any URL (try "example.com") and press Return.

**Teach:** Cmd+K is the "insert link" shortcut. It turns plain text into a clickable link. You can always remove a link later by clicking it and choosing "Remove link".

```yaml
expect:
  advance_when: window_changes
  also_advance_when: focused_element_changes
```

## Step 7 — Give the document a name

> Look at the very top of the page where it says "Untitled document". Click on that text and type a name for your document — like "My First Doc".

**Teach:** The document name appears in your Google Drive and in the browser tab. Naming it now means you'll be able to find it later.

```yaml
expect:
  match:
    role: text_field
    any_of:
      - { label_contains: "Untitled" }
      - { label_contains: "Rename" }
      - { label_contains: "title" }
  advance_when: focused_element_changes
```

## Wrap-up

> You just wrote, formatted, and named a Google Doc. Bold text, headings, and links are the three tools you'll use in nearly every document. Everything else — tables, images, comments — is built on top of this foundation.
